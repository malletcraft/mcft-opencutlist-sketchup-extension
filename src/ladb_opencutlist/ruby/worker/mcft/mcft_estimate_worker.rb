module Ladb::OpenCutList

  require 'json'
  require_relative 'mcft_push_worker'
  require_relative 'mcft_log'
  require_relative 'mcft_estimate_dialog'
  require_relative 'mcft_estimate_rules'
  require_relative '../cutlist/cutlist_generate_worker'
  require_relative '../../helper/layer_visibility_helper'
  require_relative '../../model/attributes/definition_attributes'

  # MCFT — the on-the-fly estimate, priced entirely by ERPNext.
  #
  # Amit, 2026-08-22: "sketchup model plugin will give quick printable estimate
  # on the fly ... its just a gauge to see me if client makes sense for this
  # budget." Walk a client through a number while the design is on screen,
  # without a round trip to the desk.
  #
  # NOTHING IS PRICED HERE. The plugin builds the same part-list CSV it already
  # posts to import_parts_csv and asks the server what it costs; the server
  # parses it with the code the real estimate uses, prices material off the
  # Estimation (Assumed) price list and labour off the Operation and Workstation
  # masters, and returns priced lines with a SOURCE on every one. That is the
  # rule this repo already lived by for décor — "rates enter the SketchUp
  # SESSION only ... never become a second rate card" — carried to money.
  #
  # Amit made it explicit: "always pull data of cost for labor and material from
  # erp ... plugin own cost data which is material linked or part linked should
  # get overriden. i should clearly know from where cost data is coming erp or
  # plugin." So the dialog badges every number, and the plugin's own std_prices
  # are not consulted at all.
  class McftEstimateWorker

    # THE SAME VISIBILITY TEST THE CUT LIST USES, not a second one written
    # here. CutlistGenerateWorker includes this helper and gates every entity
    # on `entity.visible? && _layer_visible?(entity.layer, ...)`; anything the
    # assembly walk does differently is a way for the two to disagree about
    # the same model, which is the fault being fixed rather than a detail of
    # it.
    include LayerVisibilityHelper

    # THE ASSEMBLY RULE LIVES IN McftEstimateRules (mcft_estimate_rules.rb),
    # where it has no SketchUp in it and tools/check-assembly-rule.rb RUNS it
    # on every push. Its history is told there: the regex has been wrong three
    # times, the walk below never. On OpenCutList 8 it also admits GROUPS, by
    # their instance name — a Smart Build module is a group
    # (docs/mcft/MOP-ON-OCL8.md §4). No copy of it is kept here.

    # into: :tab triggers an event the cutlist tab listens for, so the answer
    # lands in the estimate slide the user is already looking at. :dialog opens
    # the standalone printable window. The tab is the default because the
    # estimate screen is where Amit asked for this to live; the dialog remains
    # only because a print-only view is occasionally wanted.
    # THERE IS NO CACHED SCAN ANY MORE, and that is the fix for the worst
    # bug this estimate has had.
    #
    # A refresh used to re-price the LAST model reading instead of taking a
    # new one, on the stated ground that "after keying a rate in ERP the
    # model has not changed" (Amit, 2026-08-29, asking for a rate refresh
    # that did not re-run the estimate). The comment beside the two buttons
    # even named the danger: "Merging them would silently make one of the
    # two wrong whenever the model HAD changed." Nothing anywhere checked
    # whether it had.
    #
    # Amit, 2026-09-28: "Even though i hide a medium assembly, mop estimate
    # still use it for estimate purpose and thus wrong estimate." His console
    # showed it exactly — FOUR estimate runs, ONE assembly walk. The walk
    # happened before he hid ASMBL_M_SitOut; the three runs after it re-priced
    # that same reading and charged for an assembly no longer on screen.
    #
    # It could not be guarded cheaply. Knowing the model has changed means
    # reading the model, which is the work the cache existed to skip, and
    # every observer-based shortcut (onTransactionCommit, layer and page
    # events) is a list of mutations somebody has to keep complete — miss
    # one and the estimate is silently wrong again, which is the failure
    # mode, not a milder version of it.
    #
    # So every estimate reads the model. Refresh still exists and still does
    # what he asked for — new rates from ERP, typed minutes kept, no numbers
    # to re-enter — it simply reads the model on the way, as Recalculate has
    # always done without anyone minding the cost.

    def initialize(site_url:, api_key:, api_secret:, assembly_min: nil,
                   into: :tab, overrides: nil, size_min: nil,
                   sku: nil, hidden_group_ids: nil,
                   trip_qty: nil, trip_rate: nil, misc_remarks: nil)
      @site_url = site_url.to_s.sub(/\/+\z/, '')
      @api_key = api_key
      @api_secret = api_secret
      @assembly_min = assembly_min
      @into = into
      # {"Grooving" => {"qty" => 4, "min" => 12}} — what a person typed into
      # the estimate table. The SERVER decides which of those it will accept;
      # sending one it refuses is an error there rather than a silent no-op
      # here, which is the point.
      @overrides = overrides
      # {"large" => 90, "medium" => 30, "small" => 15}
      @size_min = size_min
      # THIS RUN CREATES NOTHING, and cannot be asked to.
      #
      # It used to carry a create_missing flag, set only when the red banner's
      # button was pressed. That was already safe — a plain Recalculate never
      # minted an Item — but it made creating a rider on a full re-price, so
      # the only way to add one Item was to re-run the whole estimate and read
      # back an answer nobody had asked for. Amit, 2026-08-29: "give me a
      # button to create material in erp. dont directly create on run."
      #
      # Creating now has its own worker and its own endpoint, and pricing has
      # no opinion about it. One path, not two.
      # The SKU this model is bound to. It is the only thing that knows which
      # real laminate the abstract slot `a` means, and the server resolves
      # against its décor map. Blank is allowed and honest: the placeholder
      # stays a placeholder and comes back marked unpriced, rather than being
      # costed off a stale stub Item that happens to carry a rate.
      @sku = sku
      # Typed trip counts and rates. The SERVER decides what it accepts; the
      # rate itself is never stored here, and never in this repo — trip costs
      # are sensitive and live in Estimate Settings on the site.
      @trip_qty = trip_qty
      @trip_rate = trip_rate
      # Free text, capped server-side at 500 characters. It explains a line
      # that is otherwise a number with no words next to it.
      @misc_remarks = misc_remarks

      # Groups hidden on the Parts List. Only the dialog knows these — see
      # McftPushWorker#_visible_groups for why Ruby cannot work it out.
      @hidden_group_ids = (hidden_group_ids || []).map(&:to_s)
    end

    def run
      model = Sketchup.active_model
      return { :errors => ['no model open'] } unless model

      # WHICH BUILD IS ACTUALLY LOADED, said on every run.
      #
      # The only line that ever reported this was "[MCFT] push — plugin <sha>",
      # and push was suspended on 2026-09-25 — so from that day nothing printed
      # the running revision at all. It went unnoticed until Amit asked whether
      # MOP was even installed on his Mac (2026-09-28) and the honest answer
      # was that no output could say.
      #
      # It matters most for the diagnostics below: console output pasted back
      # is worth little without knowing which build produced it, and "did the
      # pull take effect" should not be a guess. The dev install loads straight
      # from the clone, so this sha IS what SketchUp is running — a stronger
      # statement than `git rev-parse` in a terminal, which only says what is
      # on disk.
      #
      # IS_RBZ AND IS_LAB RIDE ALONG. OpenCutList 8 gates real behaviour on
      # IS_RBZ (Smart Join in the menu, a 300 s packing limit, how native
      # libraries load), and whether a symlinked dev install reads as an rbz
      # one is NOT CONFIRMED by anything but this line on the Mac
      # (docs/mcft/MOP-ON-OCL8.md §2.3). IS_LAB must be false, or 8 clears the
      # console at start. tools/check-estimate-notes.rb holds the stamp.
      McftLog.say("[MCFT] estimate — plugin #{McftPushWorker.plugin_rev} " \
                  "is_rbz=#{defined?(Plugin::IS_RBZ) ? Plugin::IS_RBZ.inspect : 'unknown'} " \
                  "is_lab=#{defined?(Plugin::IS_LAB) ? Plugin::IS_LAB.inspect : 'unknown'}")
      # SAID EVERY RUN, and one line rather than a first-time-only one:
      # whoever reads this output has usually scrolled to the middle of it,
      # and a path printed once at the top of a session is a path nobody
      # finds.
      McftLog.say("[MCFT]   this output is also appended to #{McftLog.path}")

      cutlist = CutlistGenerateWorker.new(part_folding: false).run
      if cutlist.errors.any?
        # SAID ON THE CONSOLE TOO, not only on the screen.
        #
        # This return sits three lines after the revision stamp, so a failed
        # cutlist produced a console showing exactly one [MCFT] line and
        # nothing else — which reads as output that was cut short rather
        # than a run that stopped. Amit hit precisely that on 2026-09-28
        # and the console could not say why.
        McftLog.say("[MCFT] estimate ABANDONED — OpenCutList could not build a " \
             "cut list: #{cutlist.errors.join(', ')}")
        McftLog.say('[MCFT]   nothing was sent to ERP, and the assembly walk below ' \
             'never ran. Fix the cut list first (usually: nothing selected, ' \
             'or the selected parts carry no material).')
        return { :errors => cutlist.errors }
      end

      # HIDDEN GROUPS ARE NOT PRICED. Amit, 2026-09-28: the estimate was
      # showing assemblies he had hidden on the Parts List, so respecting
      # the native cut list is the first step and his theory applies to
      # what survives it. The assembly WALK below is deliberately not
      # filtered: hiding a MATERIAL group says nothing about how many
      # things get assembled, and silently dropping an assembly because a
      # board was hidden would be a second bug wearing the first one's
      # clothes.
      unless @hidden_group_ids.empty?
        McftLog.say("[MCFT] estimate — ignoring #{@hidden_group_ids.size} hidden " \
             "group(s) on the Parts List")
      end
      csv = McftPushWorker.parts_csv(cutlist, @hidden_group_ids)
      _counts = _assembly_counts(model)
      payload = {
        'csv_content' => csv,
        # OpenCutList's OWN counts, kept so the PLUGIN can reconcile what
        # the server priced against what the model held. Two silent drops
        # have been found by Amit reading both tables side by side; this is
        # what makes the comparison happen every time instead.
        #
        # NOT SENT TO THE BENCH, and that is the point. Amit, 2026-09-25:
        # "unless plugin changes touches my custom development for pull do
        # not make any changes to bench as it increases testing time of
        # plugin." The plugin holds OpenCutList's totals AND receives the
        # priced rows back in the same response, so it has both sides of
        # the comparison already; doing it on the server bought nothing and
        # made every correction to it wait on a deploy and a migrate.
        # `_post_body` strips this key before the POST.
        'ocl_totals' => McftPushWorker.ocl_totals(cutlist, @hidden_group_ids),
        # WHAT THE TIMBER COSTS TO BUY, decided here and not on the bench.
        #
        # Amit, 2026-09-28: "all wastage and cossumed will always be driven
        # by MOP and not by erp." OpenCutList's own cutting volume per solid
        # wood / dimensional group, which is the finished size plus the
        # machining allowance configured on that material. The bench holds
        # back any timber missing from this map rather than pricing it at a
        # made-up offcut -- so this one IS sent, unlike ocl_totals above.
        'lumber_stock' => McftPushWorker.lumber_stock(cutlist, @hidden_group_ids),
      }
      # THE ASSEMBLY COUNT. Counted HERE, from the model, because OpenCutList
      # reports a PART's name and not the assembly that contains it — the
      # server can only see what the CSV carries. WALKED ONCE: a second walk
      # printed the whole diagnostic twice and read as two scans disagreeing.
      #
      # Built ONLY through McftEstimateRules.assembly_payload: a walk that
      # counted nothing sends NO size map, so the bench says in its own words
      # that ERP's rule priced the seven assembly steps, instead of labelling
      # that guess "plugin:ASMBL size counts" (docs/mcft/MOP-ON-OCL8.md §4.1).
      payload.merge!(McftEstimateRules.assembly_payload(_counts))
      # The walk's own lists and the notes, for THIS screen only — never
      # posted (LOCAL_ONLY_KEYS), like ocl_totals.
      payload['mcft_assembly_walk'] = _counts
      payload['mcft_notes'] = _estimate_notes(cutlist)
      # NOTHING IS REMEMBERED HERE, and that is now the design.
      #
      # This used to read typed minutes back out of the .skp and merge them
      # over every later run, so a value keyed once kept winning. Amit,
      # 2026-08-24, after seeing it work: "saving data in the model for labor
      # when selection changes is not a good idea. because it defeats purpose
      # of live estimation." He is right, and it is the same objection either
      # way round — an operation's minutes belong to the parts in front of
      # you, so a stored number that outlives the selection it was typed for
      # is not a preference being honoured, it is a stale answer overruling a
      # fresh question.
      #
      # What a person types still travels: the recalc handler reads the table
      # it is looking at and sends it. It simply does not outlive the screen.
      # The durable record is the ERP POST, which happens once the scope is
      # settled — see McftEstimateStore, which now holds only that binding.
      payload['assembly_min'] = @assembly_min unless @assembly_min.nil?
      payload['overrides'] = @overrides if @overrides.is_a?(Hash) && !@overrides.empty?
      if @size_min.is_a?(Hash) && !@size_min.empty?
        payload['assembly_min_by_size'] = @size_min
      end

      payload['sku'] = @sku unless @sku.to_s.strip.empty?
      payload['trip_qty'] = @trip_qty if @trip_qty.is_a?(Hash) && !@trip_qty.empty?
      payload['trip_rate'] = @trip_rate if @trip_rate.is_a?(Hash) && !@trip_rate.empty?
      payload['misc_remarks'] = @misc_remarks unless @misc_remarks.to_s.strip.empty?

      uri = "#{@site_url}/api/method/mallet_estimator.api.estimate_preview"
      request = Sketchup::Http::Request.new(uri, Sketchup::Http::POST)
      request.headers = {
        'Authorization' => "token #{@api_key}:#{@api_secret}",
        'Content-Type' => 'application/json',
      }
      request.body = _post_body(payload).to_json
      request.start do |req, response|
        if response && response.status_code == 200
          begin
            data = JSON.parse(response.body)['message'] || {}
            _deliver(data, payload)
          rescue StandardError => e
            _fail("estimate parse error — #{e.message}")
          end
        else
          _fail(McftPushWorker.frappe_error(response))
        end
      end
      { :success => true }
    end

    private

    # What actually goes over the wire. Everything except the keys that exist
    # only for this side of the conversation — today just OpenCutList's own
    # totals, which the reconciliation reads locally. Sending them anyway
    # would leave two implementations of one comparison, on opposite sides of
    # a deploy, free to disagree.
    def _post_body(payload)
      payload.reject { |k, _| LOCAL_ONLY_KEYS.include?(k) }
    end

    LOCAL_ONLY_KEYS = %w[ocl_totals mcft_assembly_walk mcft_notes].freeze

    def _deliver(data, payload = {})
      # The site the numbers came from, as a URL a browser can open.
      # frappe.local.site is a HOSTNAME, and the row-level "open this Item"
      # link needs a scheme — the plugin is the only side that holds the
      # configured URL, so it is the side that adds it.
      data['site_url'] = @site_url if data.is_a?(Hash)
      # The other half of the reconciliation, handed to the screen beside the
      # priced rows it has to be read against.
      # And the plugin's own readings beside them: the assembly walk (its
      # ignored and unnamed-module lists, and whether it counted anything —
      # the "not counted" warning and N4 render from THIS, not from the
      # bench's echo, which reads 0 once no size map is sent) and the notes
      # N1-N3. The same road ocl_totals already travels; none of it is posted.
      if data.is_a?(Hash)
        LOCAL_ONLY_KEYS.each { |k| data[k] = payload[k] if payload.key?(k) }
      end
      if @into == :dialog
        McftEstimateDialog.show(data)
      else
        PLUGIN.trigger_event('mcft_estimate_ready', data)
      end
    end

    # A failure must reach the SAME place the answer would have. In the tab
    # that means the event, not a messagebox: the slide is sitting on
    # "Asking ERPNext for rates..." and a modal dismissed in passing would
    # leave it saying that forever.
    def _fail(message)
      if @into == :dialog
        UI.messagebox("MCFT: estimate FAILED — #{message}")
      else
        PLUGIN.trigger_event('mcft_estimate_ready', { 'error' => message.to_s })
      end
    end

    # NOTES ONLY THE PLUGIN CAN MAKE, about a model drawn in OpenCutList 8
    # (docs/mcft/MOP-ON-OCL8.md §3.1, §5). Each is shown on the estimate slide
    # only when it has something to say. Nothing here changes what is sent:
    # the CSV describes the model as it is, and inventing an edge band or a
    # laminate to "fix" it would be a fallback.
    #
    #   cut_larger    N1: sheet-good parts whose OWN definition carries a
    #                 length or width increase. OpenCutList 8 cuts them larger;
    #                 the bench nests the finished sizes MOP sends (the same
    #                 Length/Width columns drive edge metres, so the cutting
    #                 size cannot simply be sent instead).
    #   default_named N2: pieces still named OpenCutList's default part name
    #                 ("Part", "Part#3" — what Smart Build and Paneling make).
    #   bare_fronts   N3: parts whose definition role is front_panel with no
    #                 face veneer — a door picked off a V0 carcass, priced with
    #                 no laminate.
    def _estimate_notes(cutlist)
      default = begin
        PLUGIN.get_i18n_string('default.part_single').to_s.capitalize
      rescue StandardError
        ''
      end
      cut_larger = []
      default_named = 0
      bare_fronts = []
      McftPushWorker.new(site_url: '', api_key: '', api_secret: '',
                         hidden_group_ids: @hidden_group_ids)
                    .send(:_visible_groups, cutlist).each do |group|
        sheet = group.material_type == MaterialAttributes::TYPE_SHEET_GOOD
        group.parts.each do |part|
          if sheet && (part.length_increased || part.width_increased)
            inc = []
            inc << "length +#{part.length_increase}" if part.length_increased
            inc << "width +#{part.width_increase}" if part.width_increased
            cut_larger << "#{part.name} (#{inc.join(' / ')})"
          end
          default_named += part.count.to_i if McftEstimateRules.default_part_name?(part.name, default)
          definition = part.def.respond_to?(:definition) ? part.def.definition : nil
          next unless definition
          next unless DefinitionAttributes.role_of(definition) == DefinitionAttributes::ROLE_FRONT_PANEL
          bare_fronts << part.name.to_s if (part.face_material_names || {}).empty?
        end
      end
      { 'cut_larger' => cut_larger.uniq, 'default_named' => default_named,
        'default_name' => default, 'bare_fronts' => bare_fronts.uniq }
    rescue StandardError => e
      # A note must never take the estimate down with it.
      McftLog.say("[MCFT] estimate notes skipped — #{e.message}")
      { 'cut_larger' => [], 'default_named' => 0, 'bare_fronts' => [], 'skipped' => e.message }
    end

    # Counted by ROOT INSTANCE, split by size token.
    #
    # model.entities is the root of the file, so a component placed there is
    # at the root by construction and one nested inside another is not --
    # which is the whole of the rule. Two wardrobes standing in the model are
    # two assemblies; the twenty parts inside each are none.
    #
    # Instances and not definitions: the same wardrobe definition placed
    # twice is two things to assemble, and definitions cannot tell the two
    # cases apart.
    # THE SAME SCOPE THE CUTLIST USES, which is the whole point.
    #
    # Amit, 2026-09-25: "when i am scoping in and scoping out ASMBL_L/M/S
    # material and labor are not changing. why so. verify."
    #
    # Verified, and he is half right in a way that explains the whole
    # symptom. The MATERIAL follows the scope already: parts_csv walks
    # cutlist.groups, and CutlistGenerateWorker picks model.selection when
    # something is selected and model.active_entities otherwise. The ASSEMBLY
    # COUNT did not follow anything -- it walked the model's ROOT entities
    # whatever was selected and wherever the user had scoped to. So the
    # labour line, which the count drives, was frozen at whatever the whole
    # file contains.
    #
    # Two readings of one model that disagree is worse than either being
    # wrong, because the estimate looks internally consistent. This mirrors
    # CutlistGenerateWorker's own choice exactly, so the two cannot diverge
    # again: select something and both narrow to it; scope into a component
    # and both narrow to its contents; select nothing at the top level and
    # both mean the whole file.
    #
    # "Root" therefore means the root of WHAT IS BEING LOOKED AT, which is the
    # only reading under which scoping in is meaningful at all.
    def _scope_entities(model)
      return model.selection unless model.selection.empty?
      model.active_entities || model.entities
    end

    def _assembly_counts(model)
      out = { 'large' => 0, 'medium' => 0, 'small' => 0, 'unsized' => 0 }
      ignored = []
      hidden_skipped = 0
      # THE WALK, SAID OUT LOUD. Amit, 2026-09-28: "when i select on one
      # asselmbly with ASMBL_L or M or S, its showing two M asselbies."
      #
      # Two sides can produce that number and they need opposite fixes: this
      # walk counting something twice, or the BENCH ignoring what this sends
      # and guessing from the part list instead. Reproducing the second one
      # against the server proved only that it CAN happen, not that it is what
      # happened here — and a fix built on the wrong half is worse than none.
      #
      # So the console now names every entity this walk examined and what it
      # decided, and then what was sent. Whichever side is wrong, one estimate
      # run says so.
      scope = model.selection.empty? ? 'active_entities' : 'selection'
      ents = _scope_entities(model)
      McftLog.say("[MCFT] assembly walk — scope=#{scope}, #{ents.count} entit(ies) at this level")
      unnamed = []
      ents.each do |e|
        # COMPONENTS AND GROUPS. A Smart Build module (OpenCutList 8) is a
        # GROUP at the top of the model, so a components-only walk dropped a
        # module named ASMBL_M_... silently — before the visibility test and
        # before the ignored list, so not even listed. Depth is unchanged:
        # this is still ONE level over the scope, and nothing inside an entity
        # is ever examined (docs/mcft/MOP-ON-OCL8.md §4.2).
        kind = if e.is_a?(Sketchup::ComponentInstance) then :component
               elsif e.is_a?(Sketchup::Group) then :group
               end
        next unless kind
        d = e.definition
        next if d.nil? || (kind == :component && d.image?)
        # HIDDEN ASSEMBLIES ARE NOT ASSEMBLED.
        #
        # Amit, 2026-09-28: "even though i hide few assemblies, the mop
        # estimate does not ignore it and show me in its estimate resulting
        # incorrect estimate."
        #
        # This walk counted every matching instance, hidden or not, while
        # OpenCutList's own cut list skips hidden geometry — so hiding an
        # assembly made its MATERIAL disappear and left its LABOUR behind.
        # Seven steps follow the assembly count (Assembly, Disassembly,
        # Packing, Loading, Transport, Unloading, Installation), so the
        # estimate kept charging to build, pack and install something that
        # was no longer in the cut list at all.
        #
        # Worse than a wrong total: the two halves of one estimate were
        # reading the same model by different rules. The SAME test for both
        # kinds, and it comes before any name is read.
        unless e.visible? && _layer_visible?(e.layer, true)
          hidden_skipped += 1
          McftLog.say("[MCFT]   kind=#{kind} instance=#{e.name.to_s.inspect} def=#{d.name.to_s.inspect} " \
               '-> SKIPPED (hidden in SketchUp)')
          next
        end
        # A component is named by its instance name or its definition name,
        # both of which a person sees in the Outliner; a group by its instance
        # name only (its definition is SketchUp's "Group#n").
        def_name = kind == :component ? d.name.to_s : ''
        size = McftEstimateRules.assembly_size(kind, e.name.to_s, def_name)
        if size
          out[size] += 1
          McftLog.say("[MCFT]   kind=#{kind} instance=#{e.name.to_s.inspect} def=#{d.name.to_s.inspect} -> #{size}")
        elsif McftEstimateRules.assembly_ish?(kind, e.name.to_s, def_name)
          # At the top, ASMBL-ish, and no size token: named like an assembly
          # and not counted as one. Said out loud rather than dropped.
          ignored << (e.name.to_s.empty? ? def_name : e.name.to_s)
          McftLog.say("[MCFT]   kind=#{kind} instance=#{e.name.to_s.inspect} def=#{d.name.to_s.inspect} " \
               '-> IGNORED (ASMBL with no size token)')
        elsif McftEstimateRules.unnamed_module?(kind, e.name.to_s,
                                                !PLUGIN.get_attribute(d, 'stretch_cutters').nil?)
          # Looks like an OpenCutList 8 module and carries no ASMBL name: not
          # counted, and SAID — its own list, not `ignored`, whose words
          # ("named ASMBL... but no size token") would be false for it.
          unnamed << (e.name.to_s.empty? ? '(unnamed group)' : e.name.to_s)
          McftLog.say("[MCFT]   kind=group instance=#{e.name.to_s.inspect} " \
               '-> NOT COUNTED (looks like an OpenCutList 8 module, no ASMBL name)')
        end
      end
      out['top_level'] = out['large'] + out['medium'] + out['small'] > 0
      # `unsized` keeps carrying to the bench and back, as it always has, but
      # its CONSEQUENCE has changed: these are no longer counted as Large,
      # they are not counted at all. The warning text says so.
      out['ignored'] = ignored.uniq
      out['unsized'] = ignored.size
      # WHAT WAS COUNTED, AND OVER WHAT. A number with no statement of its
      # scope is how the last mismatch stayed invisible: the estimate showed
      # a labour line that never moved and nothing said which entities it had
      # been taken from.
      out['scope'] = model.selection.empty? ? 'model' : 'selection'
      out['scope_size'] = ents.count
      out['hidden_skipped'] = hidden_skipped
      out['unnamed_modules'] = unnamed.uniq
      McftLog.say("[MCFT] assembly walk — SENDING large=#{out['large']} medium=#{out['medium']} " \
           "small=#{out['small']} ignored=#{out['ignored'].inspect} " \
           "unnamed_modules=#{out['unnamed_modules'].inspect} hidden_skipped=#{hidden_skipped}")
      unless out['top_level']
        McftLog.say('[MCFT]   no sized assembly counted, so NO size map is sent: ERP prices the ' \
             'seven assembly steps by its own rule and says so beside the count.')
      end
      McftLog.say('[MCFT]   if the estimate screen disagrees with these numbers, the bench ' \
           'ignored them — read the source in brackets beside the assembly count.')
      out
    end
  end
end
