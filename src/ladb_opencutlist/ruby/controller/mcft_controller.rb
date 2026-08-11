module Ladb::OpenCutList

  require_relative 'controller'
  require_relative '../worker/mcft/mcft_push_worker'
  require_relative '../worker/mcft/mcft_pull_worker'

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
      PLUGIN.register_command('mcft_settings') { |settings| _edit_settings }
    end

    def setup_menu(submenu)
      submenu.add_separator
      submenu.add_item('MCFT: Push part list to ERPNext') { _push }
      submenu.add_item('MCFT: Pull décor map from ERPNext') { _pull }
      submenu.add_item('MCFT: Settings…') { _edit_settings }
    end

    private

    def _settings
      {
        site_url: Sketchup.read_default(SETTINGS_SECTION, 'site_url', 'https://mcft-stg.frappe.cloud'),
        api_key: Sketchup.read_default(SETTINGS_SECTION, 'api_key', ''),
        api_secret: Sketchup.read_default(SETTINGS_SECTION, 'api_secret', ''),
        sku: Sketchup.active_model ?
               Sketchup.active_model.get_attribute('mcft', 'sku', '') : '',
      }
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

    def _guarded
      s = _settings
      if s[:api_key].empty? || s[:api_secret].empty?
        UI.messagebox('MCFT: set the site URL and API key first (MCFT: Settings…).')
        return nil
      end
      if s[:sku].to_s.empty?
        UI.messagebox('MCFT: set this model\'s Estimate SKU first (MCFT: Settings…).')
        return nil
      end
      s
    end

    def _push
      s = _guarded or return
      McftPushWorker.new(site_url: s[:site_url], api_key: s[:api_key],
                         api_secret: s[:api_secret], sku: s[:sku]).run
    end

    def _pull
      s = _guarded or return
      McftPullWorker.new(site_url: s[:site_url], api_key: s[:api_key],
                         api_secret: s[:api_secret], sku: s[:sku]).run
    end

  end
end
