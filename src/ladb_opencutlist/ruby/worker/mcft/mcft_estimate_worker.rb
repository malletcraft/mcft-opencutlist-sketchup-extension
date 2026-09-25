module Ladb::OpenCutList

  require 'json'
  require_relative 'mcft_push_worker'
  require_relative 'mcft_estimate_dialog'
  require_relative '../cutlist/cutlist_generate_worker'

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

    # THE ONLY ASSEMBLY QUALIFIER: a component at the ROOT of the model whose
    # name carries a SIZE TOKEN -- ASMBL_L, ASMBL_M or ASMBL_S.
    #
    # Amit, 2026-09-25: "component starting with ASMBL_L or ASMBL_M or ASMBL_S
    # at the root of skp file is the only assembly qualifier. ignore rest. its
    # messing with my estimate."
    #
    # WHAT THIS REPLACES, and why the old rule kept being wrong. Counting was
    # done over model.definitions -- every definition in the file, at every
    # depth -- and MCFT_ was used as a stand-in for "top level", because a
    # definition does not know where it sits. That proxy leaked in both
    # directions: parts INSIDE an assembly are named ASMBL_* too and were
    # counted beside their parent, and a bare ASMBL_* with no size token was
    # counted as LARGE, so a model holding two medium assemblies priced as ten
    # large ones. A fallback then made it worse: when no MCFT_ name was found
    # the bare list was used instead, which is precisely the pile of inner
    # parts.
    #
    # DEPTH IS THE REAL QUALIFIER and it is now tested directly, by walking
    # the model's own entities rather than its definition list. The MCFT_
    # prefix therefore stops carrying meaning it was never able to carry; it
    # is accepted because existing models use it, and ignored otherwise.
    #
    # The size token is REQUIRED. "Ignore rest" is the instruction, and a
    # nameless assembly silently priced as Large is exactly the guess that
    # made the last three estimates wrong.
    ROOT_ASSEMBLY_RE = /\A(?:MCFT[_\-]?)?ASMBL[_\-]?([LMS])(?:[_\-]|\z)/i

    # Anything ASMBL-ish that did NOT qualify, so an ignored component is
    # visible rather than silently absent. A count that quietly drops half a
    # model is the failure this whole rule exists to end.
    ASSEMBLY_ISH_RE = /ASMBL/i

    SIZE_OF = { 'L' => 'large', 'M' => 'medium', 'S' => 'small' }.freeze

    # into: :tab triggers an event the cutlist tab listens for, so the answer
    # lands in the estimate slide the user is already looking at. :dialog opens
    # the standalone printable window. The tab is the default because the
    # estimate screen is where Amit asked for this to live; the dialog remains
    # only because a print-only view is occasionally wanted.
    # THE LAST MODEL SCAN, kept so a price refresh does not need another one.
    #
    # Amit, 2026-08-29: "one more button on the estimation page which will
    # refresh cost data from erp so that i will get latest data withouth
    # rerunning the estimate." The expensive half of a run is
    # CutlistGenerateWorker walking the model; the half he wants repeated is
    # the POST. After keying a rate in ERP the model has not changed, so
    # re-reading it is work done to produce the identical CSV.
    #
    # Deliberately NOT persisted to the .skp. Amit, 2026-08-24, on storing
    # labour in the model: "it defeats purpose of live estimation." The same
    # objection applies here — a cached scan that outlived the session would
    # re-price a selection nobody is looking at any more. This lives for as
    # long as SketchUp is open and no longer, and a refresh with nothing
    # cached falls back to a full run rather than refusing.
    @@last_scan = nil

    def self.last_scan
      @@last_scan
    end

    def self.forget_scan
      @@last_scan = nil
    end

    def initialize(site_url:, api_key:, api_secret:, assembly_min: nil,
                   into: :tab, overrides: nil, size_min: nil,
                   reuse_scan: false, sku: nil,
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

      # Re-price the LAST scan instead of taking a new one. The overrides and
      # assembly minutes still come from the screen being looked at — it is
      # the model reading that is reused, never the answer.
      @reuse_scan = reuse_scan
    end

    def run
      model = Sketchup.active_model
      return { :errors => ['no model open'] } unless model

      if @reuse_scan && @@last_scan
        # A refresh answers "what does ERP say NOW about the same model",
        # so the scan is copied rather than shared: the overrides written
        # onto it below belong to this run only.
        payload = @@last_scan.dup
      else
        cutlist = CutlistGenerateWorker.new(part_folding: false).run
        return { :errors => cutlist.errors } if cutlist.errors.any?

        csv = McftPushWorker.parts_csv(cutlist)
        payload = {
          'csv_content' => csv,
          # Counted HERE, from the model, because OpenCutList reports a PART's
          # name and not the assembly that contains it — the server can only see
          # what the CSV carries. The model is the one place that knows.
          'assembly_count' => _assembly_count(model),
          'assembly_counts' => _assembly_counts(model),
          # OpenCutList's OWN counts, so the server can reconcile what it
          # priced against what the model held. Two silent drops have been
          # found by Amit reading both tables side by side; this is what makes
          # the comparison happen every time instead.
          'ocl_totals' => McftPushWorker.ocl_totals(cutlist),
        }
        # Cached BEFORE the per-run fields are added, so a later refresh
        # starts from the model reading alone and not from somebody else's
        # typed minutes.
        @@last_scan = payload.dup
      end
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
      request.body = payload.to_json
      request.start do |req, response|
        if response && response.status_code == 200
          begin
            data = JSON.parse(response.body)['message'] || {}
            _deliver(data)
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

    def _deliver(data)
      # The site the numbers came from, as a URL a browser can open.
      # frappe.local.site is a HOSTNAME, and the row-level "open this Item"
      # link needs a scheme — the plugin is the only side that holds the
      # configured URL, so it is the side that adds it.
      data['site_url'] = @site_url if data.is_a?(Hash)
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

    # Every qualifying assembly at the root of the model.
    def _assembly_count(model)
      c = _assembly_counts(model)
      c['large'] + c['medium'] + c['small']
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
      _scope_entities(model).each do |e|
        next unless e.is_a?(Sketchup::ComponentInstance)
        d = e.definition
        next if d.nil? || d.image?
        # An instance may be renamed away from its definition; either name
        # naming it an assembly is enough, because both are what a person
        # sees in the Outliner.
        name = [e.name.to_s, d.name.to_s].find { |n| ROOT_ASSEMBLY_RE.match(n) }
        if name
          out[SIZE_OF[ROOT_ASSEMBLY_RE.match(name)[1].upcase]] += 1
        elsif e.name.to_s =~ ASSEMBLY_ISH_RE || d.name.to_s =~ ASSEMBLY_ISH_RE
          # At the root, ASMBL-ish, and no size token: named like an assembly
          # and not counted as one. Said out loud rather than dropped.
          ignored << (e.name.to_s.empty? ? d.name.to_s : e.name.to_s)
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
      out['scope_size'] = _scope_entities(model).count
      out
    end
  end
end
