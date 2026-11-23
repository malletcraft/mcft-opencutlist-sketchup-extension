#!/usr/bin/env ruby
# frozen_string_literal: true
# THE UPDATER'S DECISIONS, run without SketchUp (docs/mcft/MOP-ON-OCL8.md §6.2).
#
# tools/mcft-autoupdate.rb runs on Amit's Mac at every SketchUp start and is
# the last gate between a commit and his screen. Its moves — what a --verify
# exit means, what a failed refresh means, what a CI response means, whether
# Plugins still holds MOP — are pure functions, so they are loaded and run
# here. The run itself needs SketchUp (UI.messagebox) and is read, not run.
require File.join(__dir__, 'mcft-autoupdate')
A = McftAutoupdate
fails = []
expect = lambda do |what, got, want|
  fails << "#{what}: got #{got.inspect}, expected #{want.inspect}" unless got == want
end

# --verify exits (mcft-refresh-outputs.sh): 0 clean, 10 tracked edit, 11 no
# stamp for HEAD's rbz, 12 an output changed. 10 and 12 must STOP everything:
# announcing "up to date" there is announcing MOP while stock 8 loads.
{ 0 => :ok, 10 => :modified, 11 => :refresh, 12 => :modified, 1 => :broken, 2 => :broken,
  127 => :broken }.each { |c, w| expect.call("after_verify(#{c})", A.after_verify(c), w) }
# Refresh exits: 0 done, 20 refused with src/ untouched (put the old HEAD
# back), 21 failed after touching src/ (one command: the installer).
{ 0 => :ok, 20 => :hold, 21 => :reinstall, 1 => :reinstall, 127 => :reinstall }.each do |c, w|
  expect.call("after_refresh(#{c})", A.after_refresh(c), w)
end

runs = lambda { |*rs| JSON.generate('workflow_runs' => rs) }
run = ->(name, status, concl) { { 'name' => name, 'status' => status, 'conclusion' => concl, 'html_url' => 'u' } }
expect.call('no run', A.ci_verdict_from(runs.call).first, :pending)
expect.call('only another workflow', A.ci_verdict_from(runs.call(run.call('Other', 'completed', 'success'))).first, :pending)
expect.call('in progress', A.ci_verdict_from(runs.call(run.call('MCFT checks', 'in_progress', nil))).first, :pending)
expect.call('green', A.ci_verdict_from(runs.call(run.call('MCFT checks', 'completed', 'success'))).first, :success)
expect.call('red', A.ci_verdict_from(runs.call(run.call('MCFT checks', 'completed', 'failure'))).first, :failure)
expect.call('cancelled', A.ci_verdict_from(runs.call(run.call('MCFT checks', 'completed', 'cancelled'))).first, :failure)

src = '/Users/x/dev/mop/src'
mop = { 'ladb_opencutlist' => [true, "#{src}/ladb_opencutlist"],
        'ladb_opencutlist.rb' => [true, "#{src}/ladb_opencutlist.rb"] }
expect.call('both links into the clone', A.foreign_plugins(src, ->(n) { mop[n] }), [])
stock = mop.merge('ladb_opencutlist' => [false, '/Users/x/Plugins/ladb_opencutlist'])
expect.call('an .rbz install replaced the folder', A.foreign_plugins(src, ->(n) { stock[n] }), ['ladb_opencutlist'])
elsewhere = mop.merge('ladb_opencutlist.rb' => [true, '/Users/x/old-clone/src/ladb_opencutlist.rb'])
expect.call('a link into another clone', A.foreign_plugins(src, ->(n) { elsewhere[n] }), ['ladb_opencutlist.rb'])
gone = { 'ladb_opencutlist' => [false, nil], 'ladb_opencutlist.rb' => [false, nil] }
expect.call('nothing in Plugins', A.foreign_plugins(src, ->(n) { gone[n] }).sort, %w[ladb_opencutlist ladb_opencutlist.rb])

# Read, not run: the order the design depends on, and the house rule.
body = File.read(File.join(__dir__, 'mcft-autoupdate.rb'), encoding: 'UTF-8')
runsrc = body[/^  def self\.run\(.*?^  end\n/m].to_s
v = runsrc.index("'--verify'")
f = runsrc.index('fetch origin mcft')
fails << 'run(): --verify does not come before the fetch' unless v && f && v < f
fails << 'run(): the refresh after a fast-forward is not --if-stale' unless runsrc.include?("'--if-stale'")
fails << 'run(): a refused refresh does not reset --keep to the old HEAD' unless runsrc.include?('reset --keep #{here}')
fails << 'run(): no symlink check of what will load' unless runsrc.include?('File.symlink?') && runsrc.include?('File.realpath')
fails << 'run() tells somebody to git pull (it bypasses the CI gate and the refresh)' unless runsrc.lines.grep(/git pull/).empty?
fails << 'a failure message does not name the install script' unless runsrc.scan('install_command(repo)').size >= 4

unless fails.empty?
  fails.each { |m| warn "check-autoupdate: #{m}" }
  abort "check-autoupdate: #{fails.size} problem(s)"
end
puts 'check-autoupdate: verify/refresh exits, CI verdicts and the Plugins check decide as designed; run() keeps its order'
