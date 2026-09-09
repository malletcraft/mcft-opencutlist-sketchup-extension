#!/usr/bin/env ruby
# The CSV must send the BOARD thickness for sheet goods, never the part's own
# measured geometry.
#
# OpenCutList carries both: group.std_thickness is the material's standard
# board — what its Sheet goods table prints — while part.thickness is the
# shape somebody drew. Sending the second put SG_PLY_V0_1mm on the
# YS_BATH_CABS estimate (2026-09-09): a part painted with 16 mm ply but
# modelled 1 mm thick, invisible in OCL's own table because OCL groups by the
# std thickness, and minted on the server as a board no supplier sells.
#
# This is a SOURCE check because the ruby job here parses rather than
# executes — the worker requires SketchUp to load. It cannot prove the
# behaviour; it can only stop the one line quietly going back, which is the
# specific way this bug would return. The server's nesting.implausible_board
# guard is the belt to this pair of braces.
# The worker carries UTF-8 comments (Amit's words, quoted verbatim), and a
# default US-ASCII external encoding turns the first of them into an
# ArgumentError from the regex rather than a failed check — a guard that dies
# on its own input reports nothing, which is the fault it exists to prevent.
src = File.read(File.expand_path('../src/ladb_opencutlist/ruby/worker/mcft/mcft_push_worker.rb', __dir__), encoding: 'UTF-8')

fail_with = lambda do |msg|
  warn "csv thickness: #{msg}"
  exit 1
end

unless src.include?('def _board_thickness(group)')
  fail_with.call('_board_thickness is gone — the CSV writer has lost the ' \
                 'board-vs-part thickness distinction entirely')
end

row = src[/rows << \[(.*?)\]\.map/m, 1].to_s
if row.empty?
  fail_with.call('could not find the CSV row builder to check')
end

if row.match?(/part\.length,\s*part\.width,\s*part\.thickness/)
  fail_with.call('the row sends part.thickness for every type again — a part ' \
                 'modelled off-size will mint a board nobody sells ' \
                 '(see SG_PLY_V0_1mm, 2026-09-09)')
end

unless row.include?('board_th || part.thickness')
  fail_with.call('the row no longer prefers the board thickness with the ' \
                 'part as fallback')
end

unless src.match?(/return nil unless group\.material_type == 2/)
  fail_with.call('_board_thickness no longer restricts itself to sheet ' \
                 'goods — solid wood and dimensional stock are bought at the ' \
                 'size they are cut to, and forcing a std thickness there is ' \
                 'the same bug pointed the other way')
end

puts 'csv thickness: sheet goods send the board thickness, other types the part'
