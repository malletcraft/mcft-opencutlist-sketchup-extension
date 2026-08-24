module Ladb::OpenCutList

  # WHICH ERP ESTIMATE THIS MODEL PRODUCED, kept inside the .skp.
  #
  # This module was built on 2026-08-24 to remember typed labour minutes across
  # re-runs, and Amit killed that use the same day after watching it work:
  # "saving data in the model for labor when selection changes is not a good
  # idea. because it defeats purpose of live estimation. so having text box for
  # misc also not much use full as its a runtime thing."
  #
  # He is right, and the reason generalises. An operation's minutes belong to
  # the parts currently in the estimate. Hide a component, select a different
  # set, and a number typed for the old selection is no longer a preference
  # being honoured — it is a stale answer quietly overruling a fresh question,
  # in a screen whose entire value is that it recomputes live.
  #
  # WHAT IS WORTH REMEMBERING is the other half of what he said: "posting full
  # skp file estimate to erp is valid as it will allow to keep skp and
  # estimation in sync. erp posting is done only when the overall scope is
  # finalised so thats not a frequently change thing." A post is deliberate,
  # rare, and means something has been settled. That is exactly the event worth
  # writing into the file — so the model can answer, months later, which ERP
  # estimate came out of it and whether it has been touched since.
  #
  # So: nothing here is read by the live estimate any more. It records the
  # binding a post creates, and nothing else.
  module McftEstimateStore

    DICT = 'mcft_estimate'.freeze

    # 1 was the typed-figures shape, now retired. A version 1 payload found in
    # an old model is simply ignored rather than migrated — the values it holds
    # are the ones we deliberately stopped honouring.
    VERSION = 2

    class << self

      def model
        Sketchup.active_model
      end

      # --- reading -------------------------------------------------------

      # { 'estimate' => 'MEST-EST-2026-00007', 'posted_at' => '...',
      #   'inputs_hash' => '...', 'model_path' => '...' }
      #
      # Always a Hash, never nil: every caller would otherwise need the same
      # guard and one of them would eventually forget it.
      def read_posting
        m = model
        return _empty unless m
        dict = m.attribute_dictionary(DICT, false)
        return _empty unless dict
        raw = dict['data']
        return _empty if raw.nil? || raw.to_s.empty?
        begin
          data = JSON.parse(raw.to_s)
        rescue StandardError
          # A dictionary somebody else wrote, or one we corrupted. Losing the
          # binding is bad; refusing to open the estimate is worse.
          return _empty
        end
        return _empty unless data.is_a?(Hash)
        # Anything older than VERSION held typed figures, which are no longer
        # honoured. Reading it as a posting would invent a binding that never
        # happened.
        return _empty unless data['version'].to_i >= VERSION
        {
          'estimate' => data['estimate'].to_s,
          'posted_at' => data['posted_at'].to_s,
          # The fingerprint of what was posted, NOT of the file. Amit's call,
          # 2026-08-24: "Hash the estimate inputs, not the file." A .skp hash
          # changes when a camera moves; the inputs hash changes only when the
          # estimate would come out different.
          'inputs_hash' => data['inputs_hash'].to_s,
          'model_path' => data['model_path'].to_s,
          'version' => data['version'].to_i,
        }
      end

      # --- writing -------------------------------------------------------

      # Called once, when a post to ERP succeeds. Replaces any previous
      # binding: a model produces one current estimate, and an old docname
      # kept beside a new one is a question nobody can answer later.
      def write_posting(estimate:, inputs_hash: '')
        m = model
        return false unless m
        data = {
          'version' => VERSION,
          'estimate' => estimate.to_s,
          'inputs_hash' => inputs_hash.to_s,
          'model_path' => m.path.to_s,
          'posted_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        }
        # start_operation/commit so this lands as ONE undoable step and marks
        # the model dirty — without it SketchUp can close without offering to
        # save, and the binding is gone.
        m.start_operation('MCFT estimate posted', true)
        begin
          m.set_attribute(DICT, 'data', data.to_json)
          m.commit_operation
        rescue StandardError => e
          m.abort_operation
          raise e
        end
        true
      end

      # Unbind the model from its ERP estimate. For a file copied to start a
      # new job, where carrying the old binding forward would be a lie.
      def clear
        m = model
        return false unless m
        m.start_operation('MCFT clear estimate binding', true)
        begin
          m.set_attribute(DICT, 'data', '')
          m.commit_operation
        rescue StandardError => e
          m.abort_operation
          raise e
        end
        true
      end

      # --- provenance ----------------------------------------------------

      # Where this model lives, so ERP can record which file an estimate came
      # from. Empty for a model that has never been saved.
      def model_path
        m = model
        return '' unless m
        m.path.to_s
      end

      private

      def _empty
        {
          'estimate' => '', 'posted_at' => '', 'inputs_hash' => '',
          'model_path' => '', 'version' => VERSION,
        }
      end

    end

  end

end
