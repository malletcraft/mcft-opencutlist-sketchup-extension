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

# THE RULE IS LOADED AND RUN, not pattern-matched out of the source: it
# lives in worker/mcft/mcft_estimate_rules.rb, which has no SketchUp in it so
# that this file can require it (docs/mcft/MOP-ON-OCL8.md §4.4). The walk
# that feeds it needs a model; it is held by the SOURCE assertions at the end.
WORKER_DIR = File.join(__dir__, '..', 'src', 'ladb_opencutlist', 'ruby', 'worker', 'mcft')
require File.join(WORKER_DIR, 'mcft_estimate_rules')
R = Ladb::OpenCutList::McftEstimateRules
re = R::ROOT_ASSEMBLY_RE

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

# KIND CASES — OpenCutList 8 draws Smart Build modules as GROUPS. A group is
# named by its INSTANCE name only; a component by its instance or definition
# name. [kind, instance, definition, stretch_cutters, size, ignored?, unnamed?]
KIND_CASES = [
  [:component, '',                  'ASMBL_M_WAR', false, 'medium', false, false],
  [:component, 'ASMBL_L_X',         'Part',        false, 'large',  false, false],
  [:group,     'ASMBL_M_WAR_600',   'Group#12',    true,  'medium', false, false],
  # A group's definition name is never read: it is SketchUp's Group#n.
  [:group,     '',                  'ASMBL_M_WAR', false, nil,      false, false],
  [:group,     'Part',              'Group#3',     false, nil,      false, false],
  [:group,     'ASMBL_WAR',         '',            true,  nil,      true,  false],
  [:group,     'mcft_asmbl_s_loft', 'Group#1',     false, 'small',  false, false],
  [:group,     'Wardrobe 600',      'Group#4',     true,  nil,      false, true],
  # Unnamed-module is a GROUP statement: a component never is one.
  [:component, 'Wardrobe 600',      'Wardrobe',    true,  nil,      false, false],
].freeze

KIND_CASES.each do |kind, inst, defn, cutters, size, ish, unnamed|
  def_seen = kind == :component ? defn : ''
  got = [R.assembly_size(kind, inst, defn), R.assembly_ish?(kind, inst, def_seen),
         R.unnamed_module?(kind, inst, cutters)]
  next if got == [size, ish, unnamed]
  fail_count += 1
  warn format('check-assembly-rule: %-10s %-20s def=%-14s cutters=%-5s expected size=%s ignored=%s unnamed=%s, got %s',
              kind, inst.inspect, defn.inspect, cutters, size.inspect, ish, unnamed, got.inspect)
end

# THE PAYLOAD. A walk that counted nothing sends NO size map, so the bench
# says in its own words that ERP's rule priced the steps.
zero = R.assembly_payload('large' => 0, 'medium' => 0, 'small' => 0, 'top_level' => false)
unless zero == { 'assembly_count' => 0 }
  fail_count += 1
  warn "check-assembly-rule: a zero count must send no assembly_counts, got #{zero.inspect}"
end
one = R.assembly_payload('large' => 0, 'medium' => 1, 'small' => 0, 'top_level' => true)
unless one['assembly_count'] == 1 && one['assembly_counts'].is_a?(Hash) && one['assembly_counts']['medium'] == 1
  fail_count += 1
  warn "check-assembly-rule: one medium must send the count and the map, got #{one.inspect}"
end

# THE WALK, read from its source. One level, both kinds, visibility before
# naming, and the payload built only through assembly_payload.
src = File.read(File.join(WORKER_DIR, 'mcft_estimate_worker.rb'), encoding: 'UTF-8')
walk = src[/^    def _assembly_counts\(model\)\n.*?^    end\n/m].to_s
source_rules = {
  'the walk exists' => !walk.empty?,
  'the walk iterates its scope with ents.each' => walk.include?('ents.each do |e|'),
  'the walk never descends (.entities)' => walk !~ /\.entities\b/,
  'the walk admits components' => walk.include?('e.is_a?(Sketchup::ComponentInstance)'),
  'the walk admits groups' => walk.include?('e.is_a?(Sketchup::Group)'),
  'visibility is tested before any name, for both kinds' =>
    (v = walk.index('_layer_visible?(e.layer, true)')) && (n = walk.index('McftEstimateRules.assembly_size')) && v < n &&
    walk.index('kind = if') < v,
  'the payload is built only through assembly_payload' =>
    src.include?('McftEstimateRules.assembly_payload(_counts)') && src !~ /'assembly_counts'\s*=>/,
}
source_rules.each do |what, ok|
  next if ok
  fail_count += 1
  warn "check-assembly-rule: source: #{what} — NOT TRUE"
end

if fail_count.positive?
  warn "check-assembly-rule: #{fail_count} case(s) failed"
  exit 1
end
puts "check-assembly-rule: #{CASES.size} names, #{KIND_CASES.size} kind cases, the payload shape " \
     "and #{source_rules.size} source rules hold"
