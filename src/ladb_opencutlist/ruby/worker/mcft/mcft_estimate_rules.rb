# frozen_string_literal: true
module Ladb
  module OpenCutList

    # MCFT — the estimate's RULES, with nothing of SketchUp in them.
    #
    # Pure functions on names and numbers, so tools/check-assembly-rule.rb and
    # tools/check-estimate-notes.rb can load this file and RUN them on every
    # push without a model (docs/mcft/MOP-ON-OCL8.md §4.3, §4.4, §5). The
    # walk that feeds them — McftEstimateWorker#_assembly_counts — needs a
    # model and is held by source checks instead. This file must stay free of
    # Sketchup:: and of requires: a check that cannot load it cannot run it.
    module McftEstimateRules

      # THE ONLY ASSEMBLY QUALIFIER: an entity at the TOP of the scope being
      # estimated, visible by OpenCutList's own test, whose name carries a SIZE
      # TOKEN -- ASMBL_L, ASMBL_M or ASMBL_S.
      #
      # Amit, 2026-09-25: "component starting with ASMBL_L or ASMBL_M or
      # ASMBL_S at the root of skp file is the only assembly qualifier. ignore
      # rest. its messing with my estimate."
      #
      # The size token is REQUIRED. "Ignore rest" is the instruction, and a
      # nameless assembly silently priced as Large is exactly the guess that
      # made three estimates wrong. The MCFT_ prefix is accepted because
      # existing models use it, and means nothing either way: DEPTH is the
      # qualifier, and the walk tests it directly.
      ROOT_ASSEMBLY_RE = /\A(?:MCFT[_\-]?)?ASMBL[_\-]?([LMS])(?:[_\-]|\z)/i

      # Anything ASMBL-ish that did NOT qualify, so an ignored entity is
      # visible rather than silently absent.
      ASSEMBLY_ISH_RE = /ASMBL/i

      SIZE_OF = { 'L' => 'large', 'M' => 'medium', 'S' => 'small' }.freeze

      # The names that can make an entity an assembly. A COMPONENT is named by
      # its instance name or its definition name, both of which a person sees
      # in the Outliner. A GROUP by its instance name only: its definition is
      # SketchUp's "Group#n", which nobody sees and nobody chose.
      #
      # OpenCutList 8 is why groups are here at all: a Smart Build module is a
      # GROUP at the top of the model, named after its library file — so a
      # component ASMBL_M_WAR saved to the library comes back, placed, as a
      # group named ASMBL_M_WAR. Amit's rule of a996b7f4 (components only),
      # carried to the shape 8 draws (docs/mcft/MOP-ON-OCL8.md §4.2).
      def self.assembly_names(kind, instance_name, definition_name)
        kind == :group ? [instance_name.to_s] : [instance_name.to_s, definition_name.to_s]
      end

      # kind: :component or :group. 'large' | 'medium' | 'small', or nil.
      def self.assembly_size(kind, instance_name, definition_name)
        name = assembly_names(kind, instance_name, definition_name).find { |n| ROOT_ASSEMBLY_RE.match(n) }
        name && SIZE_OF[ROOT_ASSEMBLY_RE.match(name)[1].upcase]
      end

      # Named like an assembly (ASMBL anywhere) but with no size token: listed
      # as IGNORED, never counted, never guessed.
      def self.assembly_ish?(kind, instance_name, definition_name)
        assembly_size(kind, instance_name, definition_name).nil? &&
          assembly_names(kind, instance_name, definition_name).any? { |n| n =~ ASSEMBLY_ISH_RE }
      end

      # A top-level GROUP that OpenCutList 8 built or stretched (its definition
      # carries `stretch_cutters`) with no ASMBL name at all. Not counted —
      # NO FALLBACKS, no size is ever guessed — but SAID, because a Smart Build
      # module dropped from the count silently is the failure this rule ends.
      # Smart Reshape writes the same attribute, so this is a statement ("look
      # like OpenCutList 8 modules"), not a marker.
      def self.unnamed_module?(kind, instance_name, has_cutters)
        kind == :group && has_cutters &&
          assembly_size(kind, instance_name, '').nil? &&
          instance_name.to_s !~ ASSEMBLY_ISH_RE
      end

      # WHAT THE WALK SENDS. A count of ZERO sends NO size map, so the bench
      # takes the branch it already has for "no ASMBL component in model" and
      # SAYS that ERP's own rule priced the seven steps — instead of labelling
      # its own rule "plugin:ASMBL size counts" because a map of zeros arrived
      # (mallet_estimator api.py; docs/mcft/MOP-ON-OCL8.md §4.1). The plugin
      # sends less; the bench is not changed.
      def self.assembly_payload(counts)
        total = counts['large'].to_i + counts['medium'].to_i + counts['small'].to_i
        out = { 'assembly_count' => total }
        out['assembly_counts'] = counts if total > 0
        out
      end

      # A part still carrying OpenCutList's default name: Smart Build and
      # Paneling make every part from a definition named after the translated
      # 'default.part_single' ("Part"), and SketchUp makes the names unique —
      # Part, Part#1, Part#2 — so an equality test would count only the first.
      def self.default_part_name?(name, default)
        return false if default.to_s.empty?
        /\A#{Regexp.escape(default.to_s)}(#\d+)?\z/.match?(name.to_s)
      end

    end

  end
end
