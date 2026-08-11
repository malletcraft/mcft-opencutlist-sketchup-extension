module Ladb::OpenCutList

  require 'json'
  require_relative '../../model/attributes/material_attributes'

  # MCFT — pull the SKU's context (décor slot map + current material lines
  # with rates) from ERPNext and stamp it onto the model's materials.
  #
  # This is the drift-killer: the identity of slot `b` comes from the server's
  # décor map instead of hand-typed material descriptions, and rates enter the
  # SketchUp SESSION only — they are never stored in plugin code (redaction
  # rule) and never become a second rate card.
  class McftPullWorker

    def initialize(site_url:, api_key:, api_secret:, sku:)
      @site_url = site_url.to_s.sub(/\/+\z/, '')
      @api_key = api_key
      @api_secret = api_secret
      @sku = sku
    end

    def run
      uri = "#{@site_url}/api/method/mallet_estimator.api.get_sku_context?sku=#{@sku}"
      request = Sketchup::Http::Request.new(uri, Sketchup::Http::GET)
      request.headers = { 'Authorization' => "token #{@api_key}:#{@api_secret}" }
      request.start do |req, response|
        if response && response.status_code == 200
          begin
            ctx = JSON.parse(response.body)['message'] || {}
            summary = _apply(ctx)
            UI.messagebox("MCFT: pulled #{@sku} — #{summary}")
          rescue StandardError => e
            UI.messagebox("MCFT: pull parse error — #{e.message}")
          end
        else
          code = response ? response.status_code : 'no response'
          UI.messagebox("MCFT: pull FAILED (#{code}). Check MCFT Settings.")
        end
      end
      { :success => true }
    end

    private

    # The décor map rows carry slot -> brand/code/name. Stamp each mapped slot
    # onto the matching SketchUp material's DESCRIPTION so what OCL exports is
    # the server's truth, not whatever was typed last year. Materials are
    # matched by the trailing slot letter of their name (the mallet grammar).
    def _apply(ctx)
      model = Sketchup.active_model
      return 'no model open' unless model
      decors = (ctx['decors'] || []) + (ctx['decor_edges'] || [])
      stamped = 0
      model.start_operation('MCFT Pull', true)
      begin
        decors.each do |d|
          slot = d['slot'].to_s.strip.downcase
          next if slot.empty?
          text = [ d['brand'], d['code'], d['decor_name'] ].compact.reject(&:empty?).join(' ')
          next if text.empty?
          side = slot[0] == 'a' ? 'Internal' : 'External'
          model.materials.each do |mat|
            next unless mat.name =~ /_#{Regexp.escape(slot)}(_|\z)/ || mat.name =~ /_#{Regexp.escape(slot)}\z/
            kind = mat.name.start_with?('EB_') ? 'edge band' : 'Laminate'
            mat.set_attribute('mcft', 'decor', text)
            mat.set_attribute('mcft', 'slot', slot)
            # OCL reads the material DESCRIPTION blocks in its exports; keep
            # the house format the server's decor.parse_description expects.
            desc = "#{slot} = #{side} #{kind}\nBrand = #{d['brand']}\nCode = #{d['code']}\nName = #{d['decor_name']}"
            attrs = MaterialAttributes.new(mat)
            attrs.description = desc if attrs.respond_to?(:description=)
            stamped += 1
          end
        end
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        raise e
      end
      "#{decors.length} slot(s) in map, #{stamped} material(s) stamped"
    end

  end
end
