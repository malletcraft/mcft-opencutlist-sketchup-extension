#!/usr/bin/env ruby
# ---------------------------------------------------------------------------
# MCFT — refuse syntax that SketchUp's oldest supported Ruby cannot parse.
#
# src/ladb_opencutlist.rb says "OpenCutList requires SketchUp 2017 or above",
# and SketchUp 2017 ships Ruby 2.2.4.
#
# The two tiers below are NOT the same problem, and conflating them is how a
# checker gets ignored:
#
#   FATAL  — a syntax construct. Ruby 2.2 cannot PARSE the file, so the file
#            never loads, so the extension never loads. The user does not see
#            "the estimate dialog is broken", they see OpenCutList gone. This
#            is what happened on 2026-08-22: a squiggly heredoc in
#            mcft_estimate_dialog.rb, with `ruby -c` reporting Syntax OK
#            behind it because the dev machine runs Ruby 3.3. `ruby -c` can
#            never catch this — only checking for the CONSTRUCT can.
#
#   WARN   — a method that did not exist yet. The file parses; the call raises
#            NoMethodError if it is ever reached. Bad, but contained, and
#            legitimately fine when guarded by respond_to? (upstream's
#            hash_utils.rb does exactly that), so these are reported and do
#            not fail the run.
#
# Scope is our own code. Vendored libraries under ruby/lib are upstream's and
# are excluded; policing them produces only noise nobody can act on.
#
# Usage:  ruby tools/check-ruby22.rb        (exit 1 on any FATAL)
# ---------------------------------------------------------------------------

ROOT = File.expand_path('..', __dir__)

# Syntax. Ruby 2.2 cannot parse these at all.
#
# Deliberately NOT here: `rescue` directly inside a do-block (Ruby 2.6). It is
# a genuine incompatibility but it is indistinguishable by line-regex from the
# ordinary begin/rescue and def/rescue that upstream uses in 36 places, and a
# rule with 36 false positives is a rule someone deletes. Catching it needs a
# parser, not a grep.
FATAL = [
  [/<<[~]/, 'squiggly heredoc (<<~)', 'Ruby 2.3',
   'use <<- and dedent the body by hand'],
  [/(?<![=<>!*\/%+\-&|^])&\.\s*[a-zA-Z_]/, 'safe navigation (&.)', 'Ruby 2.3',
   'use foo && foo.bar'],
]

# Methods. The file parses; the call is what would raise.
WARN = [
  [/\.dig\(/,              'Hash#dig / Array#dig', 'Ruby 2.3',
   'chain fetches: h["a"] ? h["a"]["b"] : nil'],
  [/\.match\?\(/,          'match?',               'Ruby 2.4',
   'use =~ or .match'],
  [/\.sum\s*(\{|\()/,      'Enumerable#sum(block)','Ruby 2.4',
   'use .inject(0) { |a, x| a + ... }'],
  [/\.transform_values\b/, 'transform_values',     'Ruby 2.4',
   'build it with each_with_object'],
  [/\.transform_keys\b/,   'transform_keys',       'Ruby 2.5',
   'build it with each_with_object'],
  [/\.then\b|\.yield_self\b/, 'then / yield_self', 'Ruby 2.5',
   'assign to a local instead'],
  [/\.filter_map\b/,       'filter_map',           'Ruby 2.7',
   'use .map { ... }.compact'],
]

files = Dir[File.join(ROOT, 'src/ladb_opencutlist/ruby/**/*.rb')]
        .reject { |f| f.include?('/ruby/lib/') }
        .sort

fatal = []
warn  = []
files.each do |f|
  rel = f.sub("#{ROOT}/", '')
  # Explicit UTF-8: these files carry decor, en-dashes and rupee signs, and a
  # US-ASCII default external encoding raises on the first one.
  File.read(f, :encoding => 'UTF-8').each_line.with_index do |line, i|
    next if line =~ /^\s*#/                  # a comment naming <<~ is fine
    where = "#{rel}:#{i + 1}"
    FATAL.each do |re, what, since, fix|
      fatal << [where, what, since, fix, line.strip] if line =~ re
    end
    # A respond_to? on the same line IS the guard — that is the correct way to
    # use a newer method on an older Ruby, not a violation of it.
    next if line.include?('respond_to?')
    WARN.each do |re, what, since, fix|
      warn << [where, what, since, fix, line.strip] if line =~ re
    end
  end
end

warn.each do |where, what, since, fix, src|
  puts "WARN  #{where}: #{what} is #{since} (NoMethodError if reached)"
  puts "      #{src}"
  puts "      fix: #{fix}"
end
fatal.each do |where, what, since, fix, src|
  puts "FATAL #{where}: #{what} is #{since} — file will not PARSE on SketchUp 2017"
  puts "      #{src}"
  puts "      fix: #{fix}"
end

summary = "ruby 2.2 check: #{files.length} files, " \
          "#{fatal.length} fatal, #{warn.length} warn"
puts summary
exit(fatal.empty? ? 0 : 1)
