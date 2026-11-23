# frozen_string_literal: true
# Reading a method out of upstream's plugin.rb without SketchUp: the source
# checks that hold MCFT's hunks in it (check-mcft-wiring.rb,
# check-upgrade-refused.rb) share this one reader.
#
# A method is `def name` at some indentation and runs to the first `end` at
# the same indentation — the shape every method in plugin.rb has (upstream
# formats with RubyMine). Good enough for a source check, and it fails loudly
# rather than guessing when a method cannot be found.
module McftRubySource
  PLUGIN_RB = File.expand_path('../src/ladb_opencutlist/ruby/plugin.rb', __dir__)

  def self.lines(path = PLUGIN_RB)
    File.readlines(path, encoding: 'UTF-8')
  end

  # [[name, first_line_index, last_line_index], ...] for every method.
  def self.methods_of(lines)
    out = []
    lines.each_with_index do |l, i|
      m = l.match(/\A(\s*)def\s+(?:self\.)?([A-Za-z_][A-Za-z0-9_]*[?!=]?)/)
      next unless m
      indent = m[1]
      j = (i + 1...lines.size).find { |k| lines[k] =~ /\A#{Regexp.escape(indent)}end\b/ }
      out << [m[2], i, j || lines.size - 1]
    end
    out
  end

  def self.method_body(lines, name)
    found = methods_of(lines).find { |n, _, _| n == name }
    raise "#{File.basename(PLUGIN_RB)}: def #{name} not found" unless found
    lines[found[1]..found[2]]
  end

  # Statements, crudely: non-blank lines that are not comments.
  def self.code_lines(body)
    body.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
  end
end
