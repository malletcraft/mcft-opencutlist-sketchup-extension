#!/usr/bin/env ruby
# frozen_string_literal: true
# ONE reader of docs/mcft/MCFT-PATHS, shared by tools/mcft-take-upstream.sh and
# tools/check-upstream-tree.rb, so the tool that MAKES the tree and the check
# that PROVES it cannot disagree about which paths are MCFT's.
#
# As a library:  require_relative 'mcft_paths';  McftPaths.load(root)
# As a filter:   ruby tools/mcft_paths.rb upstream < paths   (prints the paths
#                that are NOT MCFT's, one per line)
#                ruby tools/mcft_paths.rb changed           (prints changed:)
#                ruby tools/mcft_paths.rb own               (prints own:)
module McftPaths
  FILE = File.join('docs', 'mcft', 'MCFT-PATHS')

  class List
    attr_reader :own, :changed

    def initialize(own, changed)
      @own = own.freeze
      @changed = changed.freeze
      @own_dirs = own.select { |p| p.end_with?('/') }
      @own_files = own.reject { |p| p.end_with?('/') }
    end

    def own?(path)
      @own_files.include?(path) || @own_dirs.any? { |d| path.start_with?(d) }
    end

    def changed?(path)
      @changed.include?(path)
    end

    def mcft?(path)
      own?(path) || changed?(path)
    end
  end

  def self.parse(text)
    own = []
    changed = []
    into = nil
    text.each_line do |raw|
      line = raw.strip
      next if line.empty? || line.start_with?('#')
      case line
      when 'own:' then into = own
      when 'changed:' then into = changed
      else
        raise "#{FILE}: path #{line.inspect} before any own:/changed: header" unless into
        raise "#{FILE}: #{line.inspect} listed twice" if own.include?(line) || changed.include?(line)
        into << line
      end
    end
    List.new(own, changed)
  end

  def self.load(root)
    parse(File.read(File.join(root, FILE), encoding: 'UTF-8'))
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('..', __dir__)
  list = McftPaths.load(root)
  case ARGV[0]
  when 'upstream'
    $stdin.each_line { |l| p = l.chomp; puts p unless p.empty? || list.mcft?(p) }
  when 'changed' then puts list.changed
  when 'own' then puts list.own
  else
    warn 'usage: mcft_paths.rb upstream|changed|own'
    exit 2
  end
end
