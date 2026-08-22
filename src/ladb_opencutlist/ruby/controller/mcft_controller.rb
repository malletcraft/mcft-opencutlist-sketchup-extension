module Ladb::OpenCutList

  require 'json'
  require_relative 'controller'
  require_relative '../worker/mcft/mcft_push_worker'
  require_relative '../worker/mcft/mcft_pull_worker'
  require_relative '../worker/mcft/mcft_iso_worker'
  require_relative '../worker/mcft/mcft_estimate_worker'
  require_relative '../worker/mcft/mcft_estimate_dialog'

  # MCFT — the ERPNext bridge. v0 is deliberately DIALOG-FREE: three commands
  # on the OpenCutList submenu, settings via UI.inputbox, stored per-user with
  # Sketchup.write_default (the API secret never enters the model file, which
  # gets shared with clients; and never enters this repo, which is public).
  #
  # The plugin is the TRANSPORT, never the AUTHORITY: cost, pooling and the
  # offcut rack live on the server (see mcft-erpnext-context/mcft-ocl/).
  class McftController < Controller

    SETTINGS_SECTION = 'ladb_opencutlist_mcft'.freeze

    def initialize
      super('mcft')
    end

    def setup_commands
      PLUGIN.register_command('mcft_push') { |settings| _push }
      PLUGIN.register_command('mcft_pull') { |settings| _pull }
      PLUGIN.register_command('mcft_link') { |settings| _link_project }
      PLUGIN.register_command('mcft_settings') { |settings| _edit_settings }
      PLUGIN.register_command('mcft_estimate') { |settings| _estimate }
    end

    def setup_menu(submenu)
      submenu.add_separator
      submenu.add_item('MCFT: Push panel part list to ERPNext') { _push }
      submenu.add_item('MCFT: Push ISO views to ERPNext') { _push_iso }
      submenu.add_item('MCFT: Pull décor map from ERPNext') { _pull }
      submenu.add_item('MCFT: Estimate this model (ERP priced)…') { _estimate }
      submenu.add_item('MCFT: Link model to project…') { _link_project }
      submenu.add_item('MCFT: Settings…') { _edit_settings }
    end

    private

    def _settings
      model = Sketchup.active_model
      {
        site_url: Sketchup.read_default(SETTINGS_SECTION, 'site_url', 'https://mcft-stg.frappe.cloud'),
        api_key: Sketchup.read_default(SETTINGS_SECTION, 'api_key', ''),
        api_secret: Sketchup.read_default(SETTINGS_SECTION, 'api_secret', ''),
        sku: model ? model.get_attribute('mcft', 'sku', '') : '',
        # The file binding (execution/DESIGN.md §1): which project — and
        # therefore whose initials — this model's MCFT_ components belong to.
        # Set by the select-only picker, stored IN the model file so the
        # binding travels with the .skp, never with the machine.
        project: model ? model.get_attribute('mcft', 'project', '') : '',
        project_title: model ? model.get_attribute('mcft', 'project_title', '') : '',
        customer: model ? model.get_attribute('mcft', 'customer', '') : '',
        initials: model ? model.get_attribute('mcft', 'initials', '') : '',
      }
    end

    # Select-only by design: clients and projects are born in the
    # lead/opportunity phase in ERPNext — the plugin role cannot create
    # them, and this picker only chooses among what exists.
    def _link_project
      s = _guarded or return
      uri = "#{s[:site_url].sub(/\/+\z/, '')}/api/method/mallet_estimator.api.list_projects"
      request = Sketchup::Http::Request.new(uri, Sketchup::Http::GET)
      request.headers = { 'Authorization' => "token #{s[:api_key]}:#{s[:api_secret]}" }
      request.start do |req, response|
        if response && response.status_code == 200
          begin
            projects = JSON.parse(response.body)['message'] || []
            if projects.empty?
              UI.messagebox('MCFT: no open Projects on the site — create the project in ERPNext (lead/opportunity phase) first.')
            else
              labels = projects.map { |p| "#{p['title']} — #{p['customer_name']} (#{p['initials']})" }
              current = s[:project_title].to_s.empty? ? labels.first : (labels.find { |l| l.start_with?(s[:project_title]) } || labels.first)
              choice = UI.inputbox([ 'Project' ], [ current ], [ labels.join('|') ], 'MCFT: Link model to project')
              if choice
                p = projects[labels.index(choice[0])]
                model = Sketchup.active_model
                model.set_attribute('mcft', 'project', p['project'])
                model.set_attribute('mcft', 'project_title', p['title'].to_s)
                model.set_attribute('mcft', 'customer', p['customer_name'].to_s)
                model.set_attribute('mcft', 'initials', p['initials'].to_s)
                fname = File.basename(model.path.to_s)
                warn = ''
                if !fname.empty? && fname.start_with?('MCFT_') && !fname.upcase.include?("_#{p['initials']}".upcase)
                  warn = "\n\nNote: filename #{fname} does not carry #{p['initials']} — the convention is MCFT_#{p['initials']}_<Project>.skp. Files cloned from another project keep the OLD name; rename to match."
                end
                UI.messagebox("MCFT: model linked to #{p['title']} — #{p['customer_name']} (#{p['initials']}).#{warn}")
              end
            end
          rescue StandardError => e
            UI.messagebox("MCFT: link failed — #{e.message}")
          end
        else
          UI.messagebox("MCFT: link FAILED — #{McftPushWorker.frappe_error(response)}")
        end
      end
    end

    def _edit_settings
      s = _settings
      input = UI.inputbox(
        [ 'Site URL', 'API key', 'API secret', 'Estimate SKU (this model)' ],
        [ s[:site_url], s[:api_key], s[:api_secret], s[:sku] ],
        'MCFT Settings'
      )
      return unless input
      Sketchup.write_default(SETTINGS_SECTION, 'site_url', input[0])
      Sketchup.write_default(SETTINGS_SECTION, 'api_key', input[1])
      Sketchup.write_default(SETTINGS_SECTION, 'api_secret', input[2])
      # The SKU is a property of THIS model, so it rides in the model file.
      Sketchup.active_model.set_attribute('mcft', 'sku', input[3]) if Sketchup.active_model
    end

    def _guarded(need_sku: false)
      s = _settings
      if s[:api_key].empty? || s[:api_secret].empty?
        UI.messagebox('MCFT: set the site URL and API key first (MCFT: Settings…).')
        return nil
      end
      # With a container model, push discovers SKUs from component names —
      # the configured SKU is only the fallback for one-article-per-file
      # models, and pull still needs one to know whose décor map to fetch.
      if need_sku && s[:sku].to_s.empty?
        UI.messagebox('MCFT: set this model\'s Estimate SKU first (MCFT: Settings…).')
        return nil
      end
      s
    end

    # The on-the-fly estimate. Needs no SKU: it prices what is IN THE MODEL,
    # which is the whole point of being able to run it while a client is
    # sitting next to you and the article does not exist in ERP yet.
    #
    # The assembly minutes are asked for here rather than baked in, because
    # Amit asked to be able to move them: "let me modify how much time assembly
    # can take". Blank keeps ERP's own standard, and the dialog says which of
    # the two produced every line.
    def _estimate
      s = _guarded or return
      last = Sketchup.read_default(SETTINGS_SECTION, 'assembly_min', '').to_s
      answer = UI.inputbox(
        [ 'Minutes per assembly (blank = ERP standard)' ], [ last ],
        'MCFT: Estimate this model')
      return unless answer
      mins = answer[0].to_s.strip
      # to_f turns "ninety" into 0.0, and zero minutes is not a refusal — it
      # is an assembly line worth nothing, badged "edited here" so it reads
      # as deliberate. Anything that is not a positive number is rejected
      # out loud and the run falls back to ERP's own standard.
      unless mins.empty? || mins =~ /\A\d+(\.\d+)?\z/ && mins.to_f > 0
        UI.messagebox("MCFT: \"#{mins}\" is not a number of minutes.\n\n" \
                      'Using ERP standard assembly time instead.')
        mins = ''
      end
      Sketchup.write_default(SETTINGS_SECTION, 'assembly_min', mins)
      McftEstimateWorker.new(site_url: s[:site_url], api_key: s[:api_key],
                             api_secret: s[:api_secret],
                             assembly_min: mins.empty? ? nil : mins.to_f).run
    end

    def _push
      s = _guarded or return
      McftPushWorker.new(site_url: s[:site_url], api_key: s[:api_key],
                         api_secret: s[:api_secret], sku: s[:sku],
                         project: s[:project], initials: s[:initials]).run
    end

    # Separate command while the render path proves itself in the field —
    # folds into _push once trusted (execution/DESIGN.md §6.2).
    def _push_iso
      s = _guarded or return
      sent = McftIsoWorker.new(site_url: s[:site_url], api_key: s[:api_key],
                               api_secret: s[:api_secret], project: s[:project]).run
      UI.messagebox(sent > 0 ?
        "MCFT: #{sent} ISO view(s) rendered and sent — results in the Ruby console." :
        'MCFT: no SKU components found to render (name them MCFT_<ROOM>_<ARTICLE>).')
    end

    def _pull
      s = _guarded(need_sku: true) or return
      McftPullWorker.new(site_url: s[:site_url], api_key: s[:api_key],
                         api_secret: s[:api_secret], sku: s[:sku]).run
    end

  end
end
