#!/usr/bin/env ruby
# frozen_string_literal: true
# THE ESTIMATE'S NOTES AND ITS STAMP, held without SketchUp
# (docs/mcft/MOP-ON-OCL8.md §5, §2.3, §7.3 check 7).
#
# N2 counts parts still carrying OpenCutList's default name. Smart Build and
# Paneling make every part from a definition named after the translated
# 'default.part_single' ("Part"), and SketchUp makes definition names unique,
# so the parts are Part, Part#1, Part#2 — an equality test would count only the
# first. The rule is loaded and RUN.
#
# And the stamp: "[MCFT] estimate — plugin <rev> is_rbz=… is_lab=…" is the one
# line, on the path that runs every time, that says which build is loaded AND
# settles on the Mac whether a symlinked install reads as an rbz one
# (OpenCutList 8 gates Smart Join, the packing time limit and native-library
# loading on IS_RBZ). A stamp is the first thing to vanish when a path is
# rearranged — the push suspension took the last one with it.
require File.join(__dir__, '..', 'src', 'ladb_opencutlist', 'ruby', 'worker', 'mcft', 'mcft_estimate_rules')
R = Ladb::OpenCutList::McftEstimateRules

CASES = {
  ['Part', 'Part'] => true,
  ['Part#12', 'Part'] => true,
  ['Part#1', 'Part'] => true,
  ['Partition', 'Part'] => false,
  ['Part 2', 'Part'] => false,
  ['part', 'Part'] => false,
  ['Part#', 'Part'] => false,
  ['Door Part', 'Part'] => false,
  # Translated: the default name is read from i18n, never the literal "Part".
  ['Pièce#3', 'Pièce'] => true,
  ['Part#3', 'Pièce'] => false,
  # No default name known: nothing is a default name.
  ['Part', ''] => false,
}.freeze

fails = []
CASES.each do |(name, default), want|
  got = R.default_part_name?(name, default)
  fails << "default_part_name?(#{name.inspect}, #{default.inspect}) is #{got}, expected #{want}" unless got == want
end

src = File.read(File.join(__dir__, '..', 'src', 'ladb_opencutlist', 'ruby', 'worker', 'mcft',
                          'mcft_estimate_worker.rb'), encoding: 'UTF-8')
run = src[/^    def run\n.*?^    end\n/m].to_s
stamp = run.index('[MCFT] estimate — plugin')
fails << 'run() no longer prints the "[MCFT] estimate — plugin <rev>" stamp' unless stamp
fails << 'the estimate stamp no longer prints is_rbz=' unless run =~ /\[MCFT\] estimate — plugin[^\n]*\n[^\n]*is_rbz=/
fails << 'the estimate stamp no longer prints is_lab=' unless run =~ /is_rbz=[^\n]*\n[^\n]*is_lab=|is_rbz=[^\n]*is_lab=/
cut = run.index('CutlistGenerateWorker.new')
fails << 'the stamp is printed after the cut list is built, so a failed cut list hides it' if stamp && cut && stamp > cut
fails << 'the notes are no longer computed for the estimate' unless run.include?("payload['mcft_notes'] = _estimate_notes(cutlist)")
fails << 'N2 compares against a literal instead of the translated default name' unless src.include?("PLUGIN.get_i18n_string('default.part_single')")

unless fails.empty?
  fails.each { |f| warn "check-estimate-notes: #{f}" }
  abort "check-estimate-notes: #{fails.size} problem(s)"
end
puts "check-estimate-notes: #{CASES.size} default-name cases, and the stamp prints is_rbz= and is_lab= before the cut list"
