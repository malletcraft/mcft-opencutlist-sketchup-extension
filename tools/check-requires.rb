#!/usr/bin/env ruby
# Every require_relative must point at a file GIT HAS.
#
# 2026-08-24: a commit added `require_relative 'mcft_estimate_store'` and did
# not add the file — `git commit -a` stages modified tracked files and walks
# straight past a new untracked one. The require was satisfied on the machine
# that wrote it and on nobody else's, so the extension raised LoadError at load
# and the WHOLE of OpenCutList refused to start. Not the MCFT tab: all of it.
#
# ruby -c and the 2.2 syntax check cannot see this. Both walk files that exist
# on disk, and this file existed on disk — it was missing from the COMMIT. The
# only way to catch it is to ask git what it actually has, which is what this
# does.
require 'set'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)

tracked = Set.new(`git ls-files`.split("\n").map { |p| File.expand_path(p, ROOT) })
if tracked.empty?
  warn 'check-requires: git ls-files returned nothing — not a checkout?'
  exit 1
end

missing = []
checked = 0

tracked.each do |path|
  next unless path.end_with?('.rb')
  next unless File.exist?(path)
  next if path.include?('/ruby/lib/')       # vendored upstream
  dir = File.dirname(path)
  # UTF-8 explicitly: several upstream files carry accented comments, and the
  # default external encoding on a CI runner is US-ASCII, where matching a
  # regex against them raises rather than reporting anything useful.
  File.readlines(path, :encoding => 'UTF-8').each_with_index do |line, i|
    m = line.match(/^\s*require_relative\s+['"]([^'"]+)['"]/)
    next unless m
    # Interpolated paths are decided at run time — plugin.rb builds a fiddle
    # library name per platform. Nothing static can resolve those, and
    # pretending otherwise makes the check cry wolf on every run, which is how
    # a check gets ignored and then deleted.
    next if m[1].include?('#{')
    checked += 1
    target = File.expand_path(m[1], dir)
    target += '.rb' unless target.end_with?('.rb')
    next if tracked.include?(target)
    missing << [path.sub(ROOT + '/', ''), i + 1, m[1],
                File.exist?(target) ? 'ON DISK BUT NOT COMMITTED' : 'does not exist']
  end
end

if missing.empty?
  puts "check-requires: #{checked} require_relative in #{tracked.count { |p| p.end_with?('.rb') }} tracked files, all present"
  exit 0
end

missing.each do |file, line, req, why|
  puts "::error file=#{file},line=#{line}::require_relative '#{req}' — #{why}"
  warn "#{file}:#{line}: require_relative '#{req}' — #{why}"
end
warn "check-requires: #{missing.size} broken require(s)"
exit 1
