module Ladb::OpenCutList

  require 'json'
  require_relative '../cutlist/cutlist_generate_worker'
  require_relative '../../model/attributes/material_attributes'

  # MCFT — push the model's PANEL PART LIST to the ERPNext estimator with one
  # click. "Panel part list" is the house term (Amit, 2026-08-11): every part
  # is a pre-pasted panel — ply core with its laminate already pressed on both
  # faces — so veneer entries have no separate identity and are never pushed;
  # the server derives laminate and edge-band purchase quantities from the
  # panels' faces and edges.
  #
  # v0 rides the SAME import path a human uses: the whitelisted
  # `mallet_estimator.api.import_parts_csv` endpoint. The plugin serialises the
  # generated cutlist into the CSV shape the server's parser already reads, so
  # the export-CSV / save / attach / Save dance collapses into one call and
  # there is exactly ONE import pipeline to keep correct, not two.
  class McftPushWorker

    CSV_HEADERS = %w[No. Designation Quantity Length Width Thickness
                     Material\ type Material\ name
                     Edge\ Length\ 1 Edge\ Length\ 2 Edge\ Width\ 1 Edge\ Width\ 2
                     Frontside Backside Tags].freeze

    # OCL material type -> the "Material type" the server parser buckets on.
    MATERIAL_TYPE_NAMES = {
      1 => 'Sheet Goods',   # MaterialAttributes::TYPE_SOLID_WOOD is 2D-ambiguous; see map below
    }.freeze

    # Discovery (execution/DESIGN.md §1): MCFT_ is THE marker — a top-level
    # component named MCFT_<tail> is ERP-linked, everything else is invisible
    # until promoted by naming. The tail is ROOM_ARTICLE (MCFT_MB_WAR_OPT.1);
    # the customer prefix comes from the FILE's project binding, so the server
    # composes YS_MB_WAR_OPT.1 — and creates the SKU if it does not exist.
    MCFT_COMPONENT_RE = /\AMCFT_(.+)\z/
    # The pre-convention grammar (bare YS_MB_WAR component names) stays legal
    # so existing models keep pushing; resolve-only, never create.
    LEGACY_COMPONENT_RE = /\A[A-Z]{2,3}(_[A-Z0-9]{2,})+\z/

    def initialize(site_url:, api_key:, api_secret:, sku: nil, project: nil, initials: nil)
      @site_url = site_url.to_s.sub(/\/+\z/, '')
      @api_key = api_key
      @api_secret = api_secret
      @sku = sku
      @project = project.to_s
      @initials = initials.to_s
    end

    def run
      model = Sketchup.active_model
      return { :errors => [ 'mcft.error.no_model' ] } unless model

      # Which plugin build is running and what the model's materials are typed
      # as — the two facts a remote debugger cannot see. A push whose CSV lands
      # wrong is diagnosed from these lines, not from guesswork about whether
      # the auto-updater pulled (2026-08-12: an unstamped push hid exactly that).
      rev = self.class.plugin_rev
      puts "[MCFT] push — plugin #{rev}"
      type_names = %w[Unknown SolidWood SheetGood Dimensional Edge Hardware Veneer]
      model.materials.each do |m|
        t = MaterialAttributes.new(m).type
        puts "[MCFT]   material #{m.name} → #{type_names[t] || t}"
      end
      @veneer_faces = 0
      @skipped_groups = []

      targets = _sku_components(model)
      if targets.empty?
        # No SKU components: fall back to whole-model push at the configured
        # SKU (the one-article-per-file workflow keeps working).
        return { :errors => [ 'mcft.error.no_sku' ] } if @sku.to_s.empty?
        cutlist = CutlistGenerateWorker.new(part_folding: false).run
        return { :errors => cutlist.errors } if cutlist.errors.any?
        _post_csv(_to_csv(cutlist), @sku)
        _warn_if_no_laminate
        _warn_if_groups_skipped
        return { :success => true, :pushed => [ @sku ] }
      end

      mcft_targets = targets.any? { |i| i.definition.name =~ MCFT_COMPONENT_RE }
      if mcft_targets && @project.empty?
        UI.messagebox("MCFT: this model has MCFT_ components but no project binding — " \
                      "run 'MCFT: Link model to project…' first. The binding decides " \
                      "which client and project new SKUs belong to.")
        return { :errors => [ 'mcft.error.no_binding' ] }
      end

      pushed = []
      targets.each do |instance|
        name = instance.definition.name
        # The address the server resolves: an MCFT_ tail (creatable inside
        # the binding) or a legacy full code (resolve-only).
        address = (m = name.match(MCFT_COMPONENT_RE)) ? m[1] : name
        creatable = !m.nil? && !@project.empty?
        cutlist = CutlistGenerateWorker.new(
          part_folding: false,
          active_entity: instance,
          active_path: []
        ).run
        if cutlist.errors.any?
          UI.messagebox("MCFT: #{name} skipped — #{cutlist.errors.join(', ')}")
          next
        end
        _post_csv(_to_csv(cutlist), address, create: creatable)
        pushed << name
      end
      _warn_if_no_laminate
      _warn_if_groups_skipped
      { :success => true, :pushed => pushed }
    end

    private

    # Top-level component instances whose definition name is ERP-linked:
    # MCFT_-marked (the convention) or a legacy full code. Instances of the
    # SAME definition collapse to one push — a repeated article is one SKU
    # with the estimate deciding quantities.
    def _sku_components(model)
      seen = {}
      model.entities.grep(Sketchup::ComponentInstance).select { |i|
        name = i.definition.name
        next false unless name =~ MCFT_COMPONENT_RE || name =~ LEGACY_COMPONENT_RE
        next false if seen[name]
        seen[name] = true
      }
    end

    # The part-list CSV, for a caller that is not pushing.
    #
    # The estimate worker sends the SAME bytes to a different endpoint, and
    # that matters: the server parses one shape with one parser, so a priced
    # preview and an imported part list can never disagree about what the
    # model contains. Building it twice would guarantee they eventually do.
    def self.parts_csv(cutlist)
      new(site_url: '', api_key: '', api_secret: '').send(:_to_csv, cutlist)
    end

    # OCL's own totals, for the server to reconcile its pricing against.
    def self.ocl_totals(cutlist)
      new(site_url: '', api_key: '', api_secret: '').send(:_ocl_totals, cutlist)
    end

    # One row per PART (grouped, with Quantity) — the shape the server's
    # opencutlist.parse_opencutlist_csv + part_qty already handle.
    def _to_csv(cutlist)
      rows = [ CSV_HEADERS.map { |h| h.tr("\\", '') }.join(';') ]
      n = 0
      cutlist.groups.each do |group|
        type_name = _material_type_name(group.material_type)
        # A GROUP THIS CANNOT TYPE IS NOT A GROUP THAT DOES NOT MATTER.
        #
        # Veneer (6) is skipped deliberately — the server derives laminate
        # from the ply faces — and that one is announced by
        # _warn_if_no_laminate when it leaves nothing behind. Everything ELSE
        # that lands here is a material whose type the map does not know:
        # TYPE_UNKNOWN (0), which is what a material with no type set reports,
        # or a type a future OpenCutList adds. Those were dropped in silence,
        # and the estimate then simply had fewer lines than the model, with
        # nothing anywhere saying so.
        #
        # Amit, 2026-09-20: "skp and native OCL has reported casters but MOP
        # does not show casters why?" — HWD_Caster, four pieces, present in
        # OpenCutList's own Hardware table and absent from the estimate. The
        # hardware totals differed by exactly those four and nobody could have
        # known from the screen.
        if type_name.nil?
          # ||= because _to_csv is reached two ways: the push path, which
          # runs the initialiser above, and the class method parts_csv, which
          # the ESTIMATE preview calls straight into. The existing
          # `@veneer_faces += … if @veneer_faces` guards the same hazard; a
          # bare << here would raise NoMethodError on nil and take the
          # estimate screen down with it.
          (@skipped_groups ||= []) << group.material_name.to_s unless
            group.material_type == MaterialAttributes::TYPE_VENEER
          next
        end
        board_th = _board_thickness(group)
        group.parts.each do |part|
          n += 1
          edges = part.edge_material_names || {}
          faces = part.face_material_names || {}
          @veneer_faces += faces.length if @veneer_faces
          rows << [
            n,
            part.name,
            part.count,
            part.length, part.width, board_th || part.thickness,
            type_name,
            group.material_name,
            _spec(edges[:ymin]), _spec(edges[:ymax]),
            _spec(edges[:xmin]), _spec(edges[:xmax]),
            # Veneer faces are keyed by geometry, not by role: zmax is what
            # OCL's own export labels Frontside, zmin Backside (en.yml).
            _spec(faces[:zmax]), _spec(faces[:zmin]),
            (part.tags || []).join(',')
          ].map { |v| _cell(v) }.join(';')
        end
      end
      rows.join("\n")
    end

    # WHAT OPENCUTLIST ITSELF COUNTED, before this file touched any of it.
    #
    # Amit, 2026-09-25: "OCL native calculation of ply and material ... gives
    # me surprises like caster in earlier case. fix it for once. OCL native
    # material is fantastic. you just need to read it carefully without
    # messing up."
    #
    # He is right about where the fault has been. Twice now the estimate has
    # disagreed with OpenCutList's own tables and the only thing that noticed
    # was Amit reading both: HWD_Caster, four pieces, dropped because its
    # material had no type set; and SG_PLY_V0_1mm, minted because the part's
    # measured thickness was sent instead of the board's. Both were fixed
    # afterwards, one material at a time.
    #
    # This is the general form of that fix. OCL's own group/part counts travel
    # WITH the CSV, so the server can compare what it priced against what the
    # model actually contained and say so when they differ -- for every
    # material type, not just the one somebody happened to look at. A
    # reconciliation that runs every time is worth more than three fixes for
    # three materials.
    #
    # Veneer is excluded because it is deliberately not pushed: the server
    # derives laminate from the ply faces, and counting it here would report a
    # mismatch on every estimate.
    def _ocl_totals(cutlist)
      out = {}
      cutlist.groups.each do |group|
        name = _material_type_name(group.material_type)
        next if name.nil?
        t = (out[name] ||= { 'groups' => 0, 'parts' => 0, 'pieces' => 0 })
        t['groups'] += 1
        group.parts.each do |part|
          t['parts'] += 1
          t['pieces'] += part.count.to_i
        end
      end
      out
    end

    # THE BOARD YOU BUY, not the shape somebody drew.
    #
    # OpenCutList carries two thicknesses and they are not the same number:
    # group.std_thickness is the MATERIAL's standard board (what the Sheet
    # goods table prints as "SG_PLY_V0_a_a / 16 mm"), while part.thickness is
    # _def.size.thickness — the part's own measured geometry.
    #
    # This wrote part.thickness, and on 2026-09-09 that put SG_PLY_V0_1mm on
    # Amit's YS_BATH_CABS estimate: a part painted with 16 mm ply but modelled
    # 1 mm thick. His question is what found it — "how come a SG_PLY_V0_1mm
    # exists? ... but then how native cutlist have no mention of 1 mm Plywood
    # thickness". It does not, and could not: OCL GROUPS by std thickness, so
    # that part sits invisibly inside the 16 mm row while the server was told
    # 1 mm and minted a board nobody sells.
    #
    # Sheet goods only. Solid wood and dimensional stock are bought at the
    # size they are cut to, so a part's own thickness IS the right number
    # there; forcing a std thickness onto them would be the same bug pointed
    # the other way. Falls back to the part when a group has no standard —
    # an unset material must keep behaving exactly as it did before.
    def _board_thickness(group)
      return nil unless group.material_type == 2
      th = group.std_thickness.to_s.strip
      th.empty? ? nil : th
    end

    # 1=solid wood 2=sheet good 3=dimensional 4=edge 5=hardware 6=veneer
    # (MaterialAttributes::TYPE_*). Veneer parts are NOT pushed: the server
    # derives laminate from the ply faces (the press model), so pushing them
    # would double-count.
    def _material_type_name(type)
      { 1 => 'Solid Wood', 2 => 'Sheet Goods', 3 => 'Dimensional',
        4 => 'Edge Banding', 5 => 'Hardware' }[type]
    end

    def _spec(name)
      name.nil? || name.to_s.empty? ? '' : name.to_s
    end

    def _cell(v)
      s = v.to_s
      s.include?(';') || s.include?('"') || s.include?("\n") ? '"' + s.gsub('"', '""') + '"' : s
    end

    # Laminate purchase lines exist ONLY if parts carry Veneer-typed face
    # materials — an empty count means the server will show ply/edges/hardware
    # and silently no SG_LAM rows, which reads as "materials not created
    # properly". Say it at the source instead.
    # The other half of "say it at the source". A group the type map does not
    # know is a group whose parts never reach the estimate, and the person
    # reading the estimate cannot tell — the line is simply not there. Naming
    # the material is the whole value: it is what they search for in
    # OpenCutList -> Materials to set the type.
    def _warn_if_groups_skipped
      return if @skipped_groups.nil? || @skipped_groups.empty?
      names = @skipped_groups.uniq.reject(&:empty?)
      listed = names.empty? ? '(unnamed material)' : names.join("\n  ")
      UI.messagebox(
        "MCFT: #{@skipped_groups.size} material group(s) were NOT pushed " \
        "because OpenCutList has no type set for them:\n\n  #{listed}\n\n" \
        "Their parts are missing from the estimate. Open OpenCutList -> " \
        "Materials, set each one's Type (Hardware, Sheet Good, Edge Banding, " \
        "Solid Wood or Dimensional), then push again."
      )
    end

    def _warn_if_no_laminate
      return unless @veneer_faces == 0
      UI.messagebox(
        "MCFT: no laminate faces found in the model.\n\n" \
        "SG_LAM lines will be MISSING on the SKU. Laminate must be a " \
        "material of type 'Veneer' (OpenCutList → Materials) painted onto " \
        "the panel faces. Check the Ruby console for each material's type."
      )
    end

    def _post_csv(csv, sku, create: false)
      uri = "#{@site_url}/api/method/mallet_estimator.api.import_parts_csv"
      # The filename carries the plugin revision so the File list on the SKU
      # is a permanent record of WHICH build produced each import.
      payload = { 'sku' => sku, 'csv_content' => csv,
                  'filename' => "#{sku.gsub(/[^A-Za-z0-9_.-]/, '_')}_push_#{self.class.plugin_rev}.csv" }
      if create
        # The file binding decides which project (and so whose initials) a
        # new SKU belongs to; the server resolves-before-creating, so an
        # existing SKU is never duplicated (execution/DESIGN.md §1).
        payload['project'] = @project
        payload['create_if_missing'] = 1
      end
      body = JSON.generate(payload)
      request = Sketchup::Http::Request.new(uri, Sketchup::Http::POST)
      request.headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "token #{@api_key}:#{@api_secret}",
      }
      request.body = body
      request.start do |req, response|
        if response && response.status_code == 200
          begin
            msg = JSON.parse(response.body)['message'] || {}
            landed = msg['sku_code'] || msg['sku'] || sku
            UI.messagebox("MCFT: pushed #{sku} → #{landed} (plugin #{self.class.plugin_rev}) — open the SKU in ERPNext to review.")
          rescue StandardError
            UI.messagebox("MCFT: pushed #{sku} (plugin #{self.class.plugin_rev}) — open the SKU in ERPNext to review.")
          end
        else
          UI.messagebox("MCFT: push #{sku} FAILED — #{self.class.frappe_error(response)}")
        end
      end
      { :success => true }
    end

    public

    # Short git sha of the running checkout — the dev install loads straight
    # from the clone, so this IS the plugin version. Best effort: 'unknown'
    # for an rbz install or a machine without git.
    def self.plugin_rev
      @plugin_rev ||= begin
        root = File.expand_path('../../../../..', __dir__)
        sha = `git -C "#{root}" rev-parse --short HEAD 2>/dev/null`.strip
        sha.empty? ? 'unknown' : sha
      rescue StandardError
        'unknown'
      end
    end

    # What the server ACTUALLY said. Frappe answers a validation refusal with
    # HTTP 417 and puts the human message in _server_messages (a stringified
    # JSON list of stringified JSON dicts — twice-encoded, faithfully undone
    # here) or in `exception`. Blaming the URL/API key for every non-200 hid
    # the real reason on the first live run (Amit, 2026-08-11); auth failures
    # are 401/403 and say so, everything else deserves its own words.
    def self.frappe_error(response)
      return 'no response — is the site reachable?' unless response
      code = response.status_code
      body = response.body.to_s
      puts "[MCFT] HTTP #{code}: #{body[0, 600]}"     # full detail -> Ruby console
      begin
        data = JSON.parse(body)
        if data['_server_messages']
          msgs = JSON.parse(data['_server_messages']).map { |m|
            JSON.parse(m)['message'] rescue m
          }
          return "#{msgs.join(' / ')} (HTTP #{code})"
        end
        return "#{data['exception'].to_s.split("\n").first} (HTTP #{code})" if data['exception']
      rescue StandardError
      end
      case code
      when 401, 403 then "not authorised (HTTP #{code}) — check the API key in MCFT Settings"
      when 404 then "endpoint not found (HTTP 404) — check the site URL in MCFT Settings"
      else "HTTP #{code} — see the Ruby console for the full response"
      end
    end

  end
end
