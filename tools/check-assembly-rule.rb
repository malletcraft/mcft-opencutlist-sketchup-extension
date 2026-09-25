#!/usr/bin/env ruby
# The assembly qualifier, held to Amit's rule without opening SketchUp.
#
# Amit, 2026-09-25: "component starting with ASMBL_L or ASMBL_M or ASMBL_S at
# the root of skp file is the only assembly qualifier. ignore rest. its
# messing with my estimate."
#
# This rule has now been wrong three times, and each time it was the REGEX
# rather than the walk: ASMBL matched the parts inside an assembly; a missing
# size token was silently promoted to Large; MCFT_ was used as a stand-in for
# "top level" and could not do that job. The walk needs a model and cannot be
# tested here. The regex needs nothing, is where the faults were, and is
# checked on every push.
#
# Depth is asserted by the worker walking model.entities, which is structural
# and cannot be got wrong by a pattern.

# encoding: 'UTF-8' explicitly — the worker carries ellipses and en-dashes in
# its comments, and Ruby reading it as US-ASCII dies on the first match with
# "invalid byte sequence". check-csv-thickness.rb hit exactly this.
src = File.read(File.join(__dir__, '..', 'src', 'ladb_opencutlist', 'ruby',
                          'worker', 'mcft', 'mcft_estimate_worker.rb'),
                encoding: 'UTF-8')

m = src.match(/^\s*ROOT_ASSEMBLY_RE\s*=\s*(\/.*\/[a-z]*)\s*$/)
abort 'check-assembly-rule: ROOT_ASSEMBLY_RE not found' unless m
re = eval(m[1])  # rubocop:disable Security/Eval -- our own source, read above

# name => expected size, or nil for "not an assembly"
CASES = {
  # The rule, stated three ways.
  'ASMBL_L_WAR'            => 'L',
  'ASMBL_M_DRW'            => 'M',
  'ASMBL_S_SHELF'          => 'S',
  # Lower case and hyphens, because people type both.
  'asmbl_l_war'            => 'L',
  'ASMBL-L-WAR'            => 'L',
  # The MCFT_ prefix stays ACCEPTED: existing models carry it, and it now
  # means nothing either way because depth is tested directly.
  'MCFT_ASMBL_L_WAR'       => 'L',
  'MCFT_ASMBL_M_BOOKCAB'   => 'M',
  # NO SIZE TOKEN IS NOT AN ASSEMBLY. This is the whole of "ignore rest", and
  # the exact case that priced two medium assemblies as ten large ones.
  'ASMBL_WAR'              => nil,
  'ASMBL_DRW_Box'          => nil,
  'ASMBL_Door_Loft_Left'   => nil,
  'ASMBL_CARCASS_SHELF'    => nil,
  'MCFT_ASMBL_WAR'         => nil,
  # A size letter must be its own token, not the first letter of a word.
  'ASMBL_LOFT'             => nil,
  'ASMBL_MIRROR'           => nil,
  'ASMBL_SHELF'            => nil,
  # Not an assembly at all.
  'WAR_Carcass'            => nil,
  'PART_ASMBL_L_WAR'       => nil,
  ''                       => nil,
}.freeze

fail_count = 0
CASES.each do |name, want|
  got = (md = re.match(name)) ? md[1].upcase : nil
  next if got == want
  fail_count += 1
  warn format('check-assembly-rule: %-24s expected %-4s got %s',
              name.inspect, want.inspect, got.inspect)
end

if fail_count.positive?
  warn "check-assembly-rule: #{fail_count} case(s) failed"
  exit 1
end
puts "check-assembly-rule: #{CASES.size} names classified correctly"
