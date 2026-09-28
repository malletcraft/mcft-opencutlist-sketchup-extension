module Ladb::OpenCutList

  # EVERY [MCFT] LINE, ON DISK AS WELL AS ON THE CONSOLE.
  #
  # Amit, 2026-09-28: "take control of my mac and work it on your own." No
  # automation available can click SketchUp or read its Ruby Console, so the
  # nearest honest thing is to stop the diagnostics living only in a window
  # somebody has to scroll, screenshot and paste.
  #
  # It is not a convenience. Three separate diagnoses this week turned on
  # console output that had already been destroyed: the auto-updater's startup
  # line is printed once and wiped by Clear, and an instruction to clear the
  # console before running an estimate erased the very evidence it then asked
  # for. A file survives Clear, survives a restart, and can be read by a shell
  # — which is all a Mac bridge session can do.
  #
  # WHAT IT MUST NEVER CARRY: a rate, a salary, a markup or any other cost.
  # The lines routed through here are counts, names and revisions. Cost data
  # is sensitive by standing rule and this file is easy to attach to an email.
  module McftLog

    # Kept small on purpose. This is a diagnostic tail, not an archive — and
    # an unbounded log in Application Support is a bug that arrives months
    # later as a full disk.
    MAX_BYTES = 512 * 1024

    class << self

      # Both, always, and the console FIRST. If writing the file raises —
      # read-only home, sandboxed volume, a path that does not exist on some
      # future SketchUp — the line has already been printed, so the worst
      # case is the behaviour that existed before this module.
      def say(message)
        line = message.to_s
        puts line
        append(line)
        line
      end

      def path
        @path ||= begin
          home = Dir.home
          if RUBY_PLATFORM =~ /darwin/i
            File.join(home, 'Library', 'Application Support', 'mcft-estimate.log')
          elsif ENV['APPDATA'].to_s != ''
            File.join(ENV['APPDATA'], 'mcft-estimate.log')
          else
            File.join(home, 'mcft-estimate.log')
          end
        end
      end

      private

      def append(line)
        rotate
        File.open(path, 'a') do |f|
          f.puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{line}"
        end
      rescue StandardError
        # Deliberately silent. A logger that raises would take down the
        # estimate it exists to explain.
        nil
      end

      # TRUNCATED, NOT ROLLED. A second file is one more thing to ask somebody
      # to find; a single file whose oldest half is dropped answers "what just
      # happened", which is the only question ever asked of it.
      def rotate
        return unless File.exist?(path) && File.size(path) > MAX_BYTES
        keep = File.read(path)[-(MAX_BYTES / 2)..-1].to_s
        File.open(path, 'w') { |f| f.write(keep) }
      rescue StandardError
        nil
      end

    end

  end

end
