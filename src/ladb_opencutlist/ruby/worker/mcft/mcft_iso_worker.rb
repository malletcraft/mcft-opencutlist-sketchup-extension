module Ladb::OpenCutList

  require 'json'
  require 'base64'
  require 'tmpdir'
  require_relative 'mcft_push_worker'

  # MCFT — render each SKU component's ISO view and attach it as the SKU's
  # article image in ERPNext. The client estimate PRINTS article_image, so
  # the concept picture the customer sees is the CURRENT model, never a
  # stale render (execution/DESIGN.md §6.2).
  #
  # Isolation is done inside an aborted operation: hide everything except
  # the target, write the image, abort — the model is untouched by
  # construction, not by bookkeeping. The camera is saved and restored by
  # hand because the camera is not part of the undo stack.
  class McftIsoWorker

    WIDTH = 1200
    HEIGHT = 900

    def initialize(site_url:, api_key:, api_secret:, project: nil)
      @site_url = site_url.to_s.sub(/\/+\z/, '')
      @api_key = api_key
      @api_secret = api_secret
      @project = project.to_s
    end

    # Renders + uploads for every MCFT_/legacy SKU component; returns count.
    def run
      model = Sketchup.active_model
      return 0 unless model
      view = model.active_view
      cam = view.camera
      saved = [cam.eye, cam.target, cam.up, cam.perspective?]

      targets = _components(model)
      sent = 0
      targets.each do |instance|
        name = instance.definition.name
        m = name.match(McftPushWorker::MCFT_COMPONENT_RE)
        address = m ? m[1] : name
        png = _render_iso(model, view, instance)
        next unless png
        _upload(png, address, m && !@project.empty?)
        sent += 1
      end
      view.camera = Sketchup::Camera.new(saved[0], saved[1], saved[2], saved[3])
      view.invalidate
      sent
    end

    private

    def _components(model)
      seen = {}
      model.entities.grep(Sketchup::ComponentInstance).select { |i|
        n = i.definition.name
        next false unless n =~ McftPushWorker::MCFT_COMPONENT_RE || n =~ McftPushWorker::LEGACY_COMPONENT_RE
        next false if seen[n]
        seen[n] = true
      }
    end

    def _render_iso(model, view, instance)
      path = File.join(Dir.tmpdir, "mcft_iso_#{instance.definition.name.gsub(/[^A-Za-z0-9_.-]/, '_')}.png")
      model.start_operation('MCFT ISO (temporary)', true)
      begin
        model.entities.each do |e|
          next if e == instance
          e.hidden = true if e.respond_to?(:hidden=)
        end
        bb = instance.bounds
        center = bb.center
        dir = Geom::Vector3d.new(1, -1, 0.7).normalize
        eye = center.offset(dir, bb.diagonal * 1.7)
        view.camera = Sketchup::Camera.new(eye, center, Z_AXIS, true)
        view.zoom(instance)
        view.write_image(
          :filename => path, :width => WIDTH, :height => HEIGHT,
          :antialias => true, :transparent => false
        )
      rescue StandardError => e
        puts "[MCFT] iso render failed for #{instance.definition.name}: #{e.message}"
        path = nil
      ensure
        model.abort_operation   # un-hides everything; the model never changed
      end
      path && File.exist?(path) ? path : nil
    end

    def _upload(path, address, creatable)
      payload = {
        'sku' => address,
        'filename' => "#{address.gsub(/[^A-Za-z0-9_.-]/, '_')}_iso_#{McftPushWorker.plugin_rev}.png",
        'filedata' => Base64.strict_encode64(File.binread(path)),
      }
      payload['project'] = @project if creatable
      request = Sketchup::Http::Request.new(
        "#{@site_url}/api/method/mallet_estimator.api.attach_sku_image", Sketchup::Http::POST)
      request.headers = {
        'Content-Type' => 'application/json',
        'Authorization' => "token #{@api_key}:#{@api_secret}",
      }
      request.body = JSON.generate(payload)
      request.start do |req, response|
        if response && response.status_code == 200
          puts "[MCFT] iso attached for #{address}"
        else
          puts "[MCFT] iso FAILED for #{address}: #{McftPushWorker.frappe_error(response)}"
        end
      end
    end

  end
end
