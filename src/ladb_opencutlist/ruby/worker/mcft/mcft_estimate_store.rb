module Ladb::OpenCutList

  # What a person typed, kept inside the .skp.
  #
  # Amit, 2026-08-24: "time per operation i keyed in manually get lost when i
  # re run the estimate. i don't want that. because typically i will hide the
  # components if i want to take it out of estimate but still dont want to lose
  # the numbers i have keyed in manually. dont want to post it to erp at this
  # moment as well. because its WIP."
  #
  # A SketchUp attribute dictionary rides inside the model file, so it survives
  # a save, a reopen, a copy onto another machine and a re-run of the estimate.
  # That is the whole requirement: the numbers belong to the MODEL, which is the
  # container for these assemblies, and not to a server that has not been told
  # about them yet.
  #
  # Keyed by OPERATION NAME, deliberately, not by geometry. Hiding a component
  # changes what the cut list reports and therefore the quantities; it must not
  # disturb minutes typed against "Installation". Keying on the operation is
  # what makes hiding a component safe.
  #
  # WHOSE NUMBER WINS. Amit, 2026-08-24, confirming the recommendation: a value
  # typed here beats ERP's standard on a re-run, and the row says where it came
  # from. Losing it to the standard on every recompute is the exact complaint.
  # There is a per-row reset for going back deliberately.
  module McftEstimateStore

    DICT = 'mcft_estimate'.freeze

    # Bumped when the stored shape changes in a way older data cannot satisfy.
    # Read back on load so a future version can migrate rather than misread.
    VERSION = 1

    class << self

      def model
        Sketchup.active_model
      end

      # --- reading -------------------------------------------------------

      # { 'overrides' => {...}, 'size_min' => {...}, 'misc_remarks' => '...' }
      # Always a Hash, never nil: every caller would otherwise need the same
      # guard, and one of them would eventually forget it.
      def read
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
          # numbers is bad; refusing to open the estimate is worse.
          return _empty
        end
        return _empty unless data.is_a?(Hash)
        {
          'overrides' => data['overrides'].is_a?(Hash) ? data['overrides'] : {},
          'size_min' => data['size_min'].is_a?(Hash) ? data['size_min'] : {},
          'misc_remarks' => data['misc_remarks'].to_s,
          'saved_at' => data['saved_at'].to_s,
          'version' => data['version'] || VERSION,
        }
      end

      # --- writing -------------------------------------------------------

      # Replaces the stored set with what the screen is holding. NOT a merge:
      # clearing a box has to mean the value is gone, and a merge would make an
      # emptied field un-clearable.
      def write(overrides: nil, size_min: nil, misc_remarks: nil)
        m = model
        return false unless m
        data = {
          'version' => VERSION,
          'overrides' => overrides.is_a?(Hash) ? overrides : {},
          'size_min' => size_min.is_a?(Hash) ? size_min : {},
          'misc_remarks' => misc_remarks.to_s,
          'saved_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        }
        # start_operation/commit so this lands as ONE undoable step and marks
        # the model dirty — without it SketchUp can close without offering to
        # save, and the numbers are gone exactly as before.
        m.start_operation('MCFT estimate figures', true)
        begin
          m.set_attribute(DICT, 'data', data.to_json)
          m.commit_operation
        rescue StandardError => e
          m.abort_operation
          raise e
        end
        true
      end

      # Drop everything. The estimate goes back to ERP's standards on the next
      # run, which is the deliberate way back.
      def clear
        m = model
        return false unless m
        m.start_operation('MCFT clear estimate figures', true)
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
          'overrides' => {}, 'size_min' => {}, 'misc_remarks' => '',
          'saved_at' => '', 'version' => VERSION,
        }
      end

    end

  end

end
