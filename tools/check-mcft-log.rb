#!/usr/bin/env ruby
# McftLog, exercised rather than read.
#
# It is the one MCFT file that can RUN outside SketchUp — no model, no
# Sketchup:: anything — so it is the one that can be tested properly instead
# of pattern-matched. That is worth taking: a logger is exactly the kind of
# code that is never noticed when it silently does nothing, and this one
# exists because three diagnoses this week turned on console output that had
# already been cleared.
#
# The property that matters most is the LAST one: a logger that raises would
# take down the estimate it exists to explain.
require 'fileutils'
require 'tmpdir'

module Ladb; module OpenCutList; end; end
load File.join(__dir__, '..', 'src', 'ladb_opencutlist', 'ruby', 'worker',
                'mcft', 'mcft_log.rb')
Log = Ladb::OpenCutList::McftLog

fails = []
ok = lambda do |cond, what|
  puts "  #{cond ? 'ok  ' : 'FAIL'}  #{what}"
  fails << what unless cond
end

# The real path is never touched: every check runs against a temp file. A test
# that writes into ~/Library/Application Support is a test that changes the
# machine it runs on.
Dir.mktmpdir do |dir|
  path = File.join(dir, 'mcft-estimate.log')
  Log.instance_variable_set(:@path, path)

  Log.say('[MCFT] first')
  Log.say('[MCFT] second')
  body = File.read(path)
  ok.call(body.include?('[MCFT] first') && body.include?('[MCFT] second'),
          'both lines reach the file')
  ok.call(body =~ /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[MCFT\] first/,
          'each line is stamped with the time it happened')
  ok.call(Log.say('[MCFT] echo') == '[MCFT] echo',
          'say returns the line, so a caller can still use it')

  # WITHOUT THIS, a log in Application Support grows until somebody's disk is
  # full — a bug that arrives months later and looks like anything but a
  # logger.
  File.open(path, 'w') { |f| f.write('x' * (Log::MAX_BYTES + 10)) }
  Log.say('[MCFT] after the truncation')
  ok.call(File.size(path) < Log::MAX_BYTES, 'an oversized log is truncated')
  ok.call(File.read(path).include?('after the truncation'),
          'the newest line survives the truncation')
end

# THE ONE THAT MATTERS. A read-only home, a sandboxed volume or a path that
# does not exist on some future SketchUp must cost the estimate nothing.
Log.instance_variable_set(:@path, '/nonexistent-dir-for-this-check/mcft.log')
raised = nil
begin
  Log.say('[MCFT] an unwritable path is not an error')
rescue StandardError => e
  raised = e
end
ok.call(raised.nil?,
        "say does not raise when the file cannot be written#{raised ? " — #{raised.class}" : ''}")

# And the standing rule, checked on the source because it is about what the
# lines CARRY rather than what the module does: the HTTP body holds rates and
# must stay in the Ruby console.
push = File.read(File.join(__dir__, '..', 'src', 'ladb_opencutlist', 'ruby',
                           'worker', 'mcft', 'mcft_push_worker.rb'),
                 encoding: 'UTF-8')
ok.call(push =~ /^\s*puts "\[MCFT\] HTTP / && push !~ /McftLog\.say\("\[MCFT\] HTTP /,
        'the HTTP response body is never written to the log file')

if fails.any?
  fails.each { |f| warn "::error::check-mcft-log: #{f}" }
  warn "#{fails.size} check(s) failed"
  exit 1
end
puts 'McftLog: writes, stamps, truncates, and never raises'
