# frozen_string_literal: true
#
# PUSH TO ERPNext STAYS OFF UNTIL MRP IS READY.
#
# Amit, 2026-09-25: "For some time i do not want to push any data from sketchup
# to erp as its not ready yet. but pull is fine like labor cost phases, material
# cost etc. so that plugin will be ready faster."
#
# The two push commands were disabled rather than deleted, so that the plugin
# says WHY on screen instead of a feature quietly disappearing — and so that
# McftPushWorker.parts_csv and .ocl_totals, which the ESTIMATE (the pull path)
# depends on, keep working. The cost of that choice is that the workers are
# still sitting there, one line away from being called again.
#
# This is the line. A source check, because the Ruby job parses rather than
# executes: it asserts that neither _push nor _push_iso constructs its worker.
# Lifting the suspension means deleting this file in the same commit, which is
# a deliberate act somebody has to explain in a commit message.
require 'English'

src = File.read(
  File.expand_path('../src/ladb_opencutlist/ruby/controller/mcft_controller.rb', __dir__),
  encoding: 'UTF-8'
)

fail_count = 0
say = lambda do |msg|
  puts "::error file=src/ladb_opencutlist/ruby/controller/mcft_controller.rb::#{msg}"
  fail_count += 1
end

# The body of a def, up to the next def at the same indentation.
def body_of(src, name)
  m = src.match(/^    def #{name}\b(.*?)^    end$/m)
  m && m[1]
end

%w[_push _push_iso].each do |meth|
  body = body_of(src, meth)
  if body.nil?
    say.call("#{meth} not found — if it was renamed, this check has to be " \
             'renamed with it, not left passing by accident')
    next
  end
  if body =~ /Mcft(Push|Iso)Worker\.new/
    say.call("#{meth} constructs a push worker again. Pushing to ERPNext is " \
             'suspended until MRP is ready (Amit, 2026-09-25). If MRP IS ready, ' \
             'delete tools/check-push-suspended.rb in the same commit and say so.')
  end
  unless body.include?('SUSPENDED_UNTIL_MRP')
    say.call("#{meth} no longer tells the user why nothing was sent. A command " \
             'that does nothing in silence is worse than one that is missing.')
  end
end

unless src.include?('SUSPENDED_UNTIL_MRP =')
  say.call('SUSPENDED_UNTIL_MRP is gone — the message the two commands show.')
end

if fail_count.zero?
  puts 'push to ERPNext is suspended in both commands, and both say why'
else
  exit 1
end
