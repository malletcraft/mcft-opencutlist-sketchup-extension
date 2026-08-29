module Ladb::OpenCutList

  require 'json'
  require_relative 'mcft_push_worker'

  # MCFT — create the Items ERP has never heard of, and nothing else.
  #
  # Amit, 2026-08-29: "give me a button to create material in erp. dont
  # directly create on run. need bot button. one to create all missing
  # material and one on each line."
  #
  # Creating used to be a flag on the estimate run, set only when the red
  # banner's button was pressed. That was safe but wrong-shaped: the only way
  # to add one Item was to re-run the whole estimate, which re-reads the
  # model, re-prices every line and hands back an answer nobody asked for. It
  # also made a PER-LINE button impossible to write honestly — a run that
  # creates "the missing ones" cannot report what happened to the single code
  # somebody clicked.
  #
  # So this worker does the one thing, over an endpoint that does the one
  # thing, and reports per code: created, already existed, or refused with a
  # reason. The caller decides what to do next; it prices nothing itself.
  #
  # It never sends a rate, and there is no parameter by which it could. The
  # Item is a fact about what the model uses; the rate is a decision a person
  # makes at the desk.
  class McftCreateMaterialsWorker

    # @param codes [Array<String>] OpenCutList codes, e.g. SG_PLY_V1_...
    def initialize(site_url:, api_key:, api_secret:, codes:)
      @site_url = site_url.to_s.sub(/\/+\z/, '')
      @api_key = api_key
      @api_secret = api_secret
      @codes = Array(codes).map { |c| c.to_s.strip }.reject(&:empty?).uniq
    end

    def run
      if @codes.empty?
        _deliver({ 'error' => 'nothing to create' })
        return { :success => true }
      end

      uri = "#{@site_url}/api/method/mallet_estimator.api.create_materials"
      request = Sketchup::Http::Request.new(uri, Sketchup::Http::POST)
      request.headers = {
        'Authorization' => "token #{@api_key}:#{@api_secret}",
        'Content-Type' => 'application/json',
      }
      # POST, and the server refuses anything else. Frappe rolls a GET back:
      # the insert happens, the reply says created, and the Item is gone when
      # the request ends. Proved on mcft-stg, 2026-08-29.
      request.body = { 'codes' => @codes }.to_json
      request.start do |req, response|
        if response && response.status_code == 200
          begin
            data = JSON.parse(response.body)['message'] || {}
            _deliver(data)
          rescue StandardError => e
            _deliver({ 'error' => "create parse error — #{e.message}" })
          end
        else
          _deliver({ 'error' => McftPushWorker.frappe_error(response) })
        end
      end
      { :success => true }
    end

    private

    # The answer goes back to the slide the button lives on, never to a
    # messagebox. A modal dismissed in passing leaves the row saying
    # "Creating…" for ever, which is the failure shape this project keeps
    # meeting: silence and success looking identical.
    def _deliver(data)
      PLUGIN.trigger_event('mcft_materials_created', data)
    end

  end

end
