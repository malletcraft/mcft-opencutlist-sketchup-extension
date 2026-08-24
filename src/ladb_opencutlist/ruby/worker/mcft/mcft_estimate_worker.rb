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

    # The assembly marker. A component named ASMBL<something> is one assembly,
    # and the count of them drives the Assembly labour line. Amit: "the
    # component which starts with ASMBL is the assembly which goes into
    # assemblies line of labor."
    ASSEMBLY_RE = /\AASMBL/i

    # ASMBL_L_WAR, ASMBL_M_DRW, ASMBL_S_SHELF. Amit, 2026-08-23: "we deal with
    # three size of assembly, Large - carcass, medium drawers , small like
    # shelfs ... so that i can do a better job of estimating the time."
    #
    # A name with no size token counts as LARGE: every model drawn before this
    # convention says plain ASMBL_WAR, and those are carcasses.
    ASSEMBLY_SIZE_RE = /\AASMBL[_\-]?([LMS])(?:[_\-]|\z)/i
    SIZE_OF = { 'L' => 'large', 'M' => 'medium', 'S' => 'small' }.freeze

    # into: :tab triggers an event the cutlist tab listens for, so the answer
    # lands in the estimate slide the user is already looking at. :dialog opens
    # the standalone printable window. The tab is the default because the
    # estimate screen is where Amit asked for this to live; the dialog remains
    # only because a print-only view is occasionally wanted.
    def initialize(site_url:, api_key:, api_secret:, assembly_min: nil,
                   into: :tab, overrides: nil, size_min: nil)
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
    end

    def run
      model = Sketchup.active_model
      return { :errors => ['no model open'] } unless model

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
      }
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

    # Distinct ASMBL component DEFINITIONS, each multiplied by how many
    # instances of it the model carries. Two wardrobes is two assemblies; one
    # definition used twenty times inside another is still counted by its
    # instances, because each one gets assembled.
    def _assembly_count(model)
      c = _assembly_counts(model)
      c['large'] + c['medium'] + c['small']
    end

    # The same instance count, split by the size token in the name.
    def _assembly_counts(model)
      out = { 'large' => 0, 'medium' => 0, 'small' => 0, 'unsized' => 0 }
      model.definitions.each do |d|
        next unless d.name =~ ASSEMBLY_RE
        next if d.image? || d.group?
        n = d.count_used_instances
        m = ASSEMBLY_SIZE_RE.match(d.name)
        if m
          out[SIZE_OF[m[1].upcase]] += n
        else
          out['large'] += n
          out['unsized'] += n
        end
      end
      out
    end
  end
end
