#!/usr/bin/env ruby
# ---------------------------------------------------------------------------
# MCFT — refuse syntax older SketchUp Rubies cannot parse.
#
# THE FLOOR IS SKETCHUP 2021, WHICH SHIPS RUBY 2.7.
#
# Amit, 2026-08-24: "2017 is not a target, drop the ruby 2.2 constraint." It
# was never a hypothetical constraint — a squiggly heredoc took the whole
# extension down on 2026-08-22 — but it was pinned to a SketchUp nobody here
# runs. Amit is on 2026 (Ruby 3.2.2).
#
# RAISED rather than deleted, and the difference matters. Every rule the old
# file carried named Ruby 2.3 to 2.7, so a 2.7 floor makes all of them legal at
# a stroke: squiggly heredocs, safe navigation, dig, match?, transform_values,
# filter_map — write them freely. What remains is a guard against Ruby 3.0+
# syntax, which is real: a studio on SketchUp 2021 or 2022 is a plausible user
# of a productised MCFT, and `case/in` in one file would take their whole
# extension down exactly as the heredoc did.
#
# To move the floor again, change RUBY_FLOOR and the FATAL list together, and
# the version gate in src/ladb_opencutlist.rb with them.
#
#   SketchUp 2017-2020 -> Ruby 2.2      SketchUp 2023-2024 -> Ruby 3.1
#   SketchUp 2021-2022 -> Ruby 2.7      SketchUp 2025-2026 -> Ruby 3.2
#
# The two tiers below are NOT the same problem, and conflating them is how a
# checker gets ignored:
#
#   FATAL  — a syntax construct. The older Ruby cannot PARSE the file, so the
#            file never loads, so the extension never loads. The user does not
#            see "the estimate dialog is broken", they see OpenCutList gone.
#            `ruby -c` can never catch this on a modern dev machine — only
#            checking for the CONSTRUCT can.
#
#   WARN   — a method that did not exist yet. The file parses; the call raises
#            NoMethodError if reached. Bad, but contained, and legitimately
#            fine when guarded by respond_to?, so these are reported and do not
#            fail the run.
#
# Scope is our own code. Vendored libraries under ruby/lib are upstream's and
# are excluded; policing them produces only noise nobody can act on.
#
# Usage:  ruby tools/check-ruby-floor.rb        (exit 1 on any FATAL)
# ---------------------------------------------------------------------------

RUBY_FLOOR = '2.7 (SketchUp 2021)'.freeze

ROOT = File.expand_path('..', __dir__)

# Syntax Ruby 2.7 cannot parse. The list is SHORT on purpose.
#
# Most Ruby 3.x syntax cannot be told apart from ordinary code by a line
# regex, and the first draft of this list proved it the hard way: a rule for
# rightward assignment matched every `rescue StandardError => e` and every
# `:key => value` hash literal, and a rule for endless methods matched every
# `def name=(value)` setter. 107 false positives across a codebase containing
# no Ruby 3 syntax at all.
#
# That is not a tuning problem, it is the same lesson the old file already
# recorded about `rescue` inside a do-block: catching it needs a parser, not a
# grep. A rule that cries wolf is a rule someone deletes, and it takes the
# real guarantee with it. So only constructs that are unambiguous on one line
# are listed, and the rest are simply not claimed.
FATAL = [
  [/\bData\.define\b/, 'Data.define', 'Ruby 3.2', 'use Struct.new'],
]

# Methods. The file parses; the call is what would raise.
#
# The 2.3-to-2.7 entries this file used to carry are GONE, not relaxed: at a
# 2.7 floor dig, match?, sum(block), transform_values, transform_keys, then,
# filter_map, squiggly heredocs and safe navigation are all simply available.
WARN = [
  [/\.except\(/,      'Hash#except',      'Ruby 3.0', 'use reject { |k, _| ... }'],
  [/\.intersect\?\(/, 'Array#intersect?', 'Ruby 3.1', 'use (a & b).any?'],
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
  puts "FATAL #{where}: #{what} is #{since} — file will not PARSE below Ruby #{RUBY_FLOOR}"
  puts "      #{src}"
  puts "      fix: #{fix}"
end

summary = "ruby floor check (#{RUBY_FLOOR}): #{files.length} files, " \
          "#{fatal.length} fatal, #{warn.length} warn"
puts summary
exit(fatal.empty? ? 0 : 1)
