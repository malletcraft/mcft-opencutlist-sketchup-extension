module Ladb::OpenCutList

  require 'json'
  require_relative '../cutlist/cutlist_generate_worker'

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

    # A component name is an SKU address when it follows the house grammar:
    # CUSTOMER_ROOM_ARTICLE... (YS_MB_WAR, YS_KIT_BAS_CAB). The container model
    # holds the floor plan plus one such component per article (Amit,
    # 2026-08-11), so push DISCOVERS the SKUs instead of being told one.
    SKU_COMPONENT_RE = /\A[A-Z]{2,3}(_[A-Z0-9]{2,})+\z/

    def initialize(site_url:, api_key:, api_secret:, sku: nil)
      @site_url = site_url.to_s.sub(/\/+\z/, '')
      @api_key = api_key
      @api_secret = api_secret
      @sku = sku
    end

    def run
      model = Sketchup.active_model
      return { :errors => [ 'mcft.error.no_model' ] } unless model

      targets = _sku_components(model)
      if targets.empty?
        # No SKU components: fall back to whole-model push at the configured
        # SKU (the one-article-per-file workflow keeps working).
        return { :errors => [ 'mcft.error.no_sku' ] } if @sku.to_s.empty?
        cutlist = CutlistGenerateWorker.new(part_folding: false).run
        return { :errors => cutlist.errors } if cutlist.errors.any?
        _post_csv(_to_csv(cutlist), @sku)
        return { :success => true, :pushed => [ @sku ] }
      end

      pushed = []
      targets.each do |instance|
        code = instance.definition.name
        cutlist = CutlistGenerateWorker.new(
          part_folding: false,
          active_entity: instance,
          active_path: []
        ).run
        if cutlist.errors.any?
          UI.messagebox("MCFT: #{code} skipped — #{cutlist.errors.join(', ')}")
          next
        end
        _post_csv(_to_csv(cutlist), code)
        pushed << code
      end
      { :success => true, :pushed => pushed }
    end

    private

    # Top-level component instances whose definition name reads as an SKU
    # code. Instances of the SAME definition collapse to one push — a
    # repeated article is one SKU with the estimate deciding quantities.
    def _sku_components(model)
      seen = {}
      model.entities.grep(Sketchup::ComponentInstance).select { |i|
        name = i.definition.name
        next false unless name =~ SKU_COMPONENT_RE
        next false if seen[name]
        seen[name] = true
      }
    end

    # One row per PART (grouped, with Quantity) — the shape the server's
    # opencutlist.parse_opencutlist_csv + part_qty already handle.
    def _to_csv(cutlist)
      rows = [ CSV_HEADERS.map { |h| h.tr("\\", '') }.join(';') ]
      n = 0
      cutlist.groups.each do |group|
        type_name = _material_type_name(group.material_type)
        next if type_name.nil?
        group.parts.each do |part|
          n += 1
          edges = part.edge_material_names || {}
          faces = part.face_material_names || {}
          rows << [
            n,
            part.name,
            part.count,
            part.length, part.width, part.thickness,
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

    def _post_csv(csv, sku)
      uri = "#{@site_url}/api/method/mallet_estimator.api.import_parts_csv"
      body = JSON.generate({ 'sku' => sku, 'csv_content' => csv,
                             'filename' => "#{sku}_push.csv" })
      request = Sketchup::Http::Request.new(uri, Sketchup::Http::POST)
      request.headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "token #{@api_key}:#{@api_secret}",
      }
      request.body = body
      request.start do |req, response|
        if response && response.status_code == 200
          UI.messagebox("MCFT: pushed #{sku} — open the SKU in ERPNext to review.")
        else
          UI.messagebox("MCFT: push #{sku} FAILED — #{self.class.frappe_error(response)}")
        end
      end
      { :success => true }
    end

    public

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
