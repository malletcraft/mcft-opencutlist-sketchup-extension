#!/bin/bash
# ---------------------------------------------------------------------------
# MCFT dev install for SketchUp on macOS — symlink once, then every update is
#   git pull && restart SketchUp
#
# What it does:
#   1. finds your newest SketchUp Plugins folder
#   2. removes any installed stock OpenCutList (files only — uninstall via
#      Extension Manager first if it was installed from Extension Warehouse)
#   3. symlinks THIS CLONE's src/ into Plugins
#   4. extracts the native engines (Packy/Clippy/Imagy dylibs) out of
#      dist/ladb_opencutlist.rbz into the tree — they are not in git, and
#      without them cutting diagrams cannot load (everything else runs)
#
# Usage:  ./tools/dev-install-mac.sh
# Update: git pull   (re-run this script only if upstream bumps the binaries)
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

PLUG=$(ls -d "$HOME/Library/Application Support/SketchUp "*/SketchUp/Plugins 2>/dev/null | sort | tail -1)
[ -n "$PLUG" ] || { echo "No SketchUp Plugins folder found under ~/Library/Application Support"; exit 1; }
echo "Plugins folder: $PLUG"

# 1. clear stock OCL / previous copies (symlinks or real dirs)
rm -rf "$PLUG/ladb_opencutlist" "$PLUG/ladb_opencutlist.rb"

# 2. BUILD OUTPUTS from the shipped rbz -> src tree. The repo holds SOURCE
#    (twig templates, less, i18n-src); SketchUp loads the BUILT files —
#    compiled dialog html, bundled js/css, i18n yml, native engines — which
#    upstream's gulp build writes into src/ and .gitignore excludes. Without
#    them the extension dies at first get_i18n_string (missing en.yml).
#    Copy every rbz file missing from src; NEVER overwrite src files, so the
#    branded loader and live source always win. Re-runs just top up.
#    (unzip -n = never overwrite; rbz entries are 'ladb_opencutlist/...' so
#    -d src lands them exactly at src/ladb_opencutlist/...)
unzip -nq "$REPO/dist/ladb_opencutlist.rbz" 'ladb_opencutlist/*' -d "$REPO/src"
echo "Build outputs synced from dist rbz (i18n, dialog html, js/css, native engines)"

# 3. symlink the live source
ln -s "$REPO/src/ladb_opencutlist.rb" "$PLUG/ladb_opencutlist.rb"
ln -s "$REPO/src/ladb_opencutlist"    "$PLUG/ladb_opencutlist"

# 4. the auto-updater: every SketchUp start fast-forwards this clone from
#    GitHub BEFORE OpenCutList loads, so "restart SketchUp" IS the update.
#
#    IT WILL NOT PULL A COMMIT WHOSE CI IS NOT GREEN. Added 2026-09-03, after
#    a commit with a stale twig bundle went to this Mac and its feature could
#    not appear: MCFT checks had ALREADY caught it and gone red, and the
#    dispatch happened anyway because nobody read the run. A guard that is
#    only consulted when someone remembers is not a guard, so the last gate
#    now consults it — on the machine, every start, whether or not anybody
#    looked.
#    The leading "!" makes it load first (SketchUp loads Plugins in sorted
#    order). Never merges — if the clone has local edits it just skips, it
#    cannot destroy work. A REAL failure (auth, ssh-in-GUI, local edits) is
#    LOUD — a messagebox with the reason and the Terminal fix — because two
#    silent no-op "updates" cost a day of debugging a stale plugin
#    (2026-08-12). Offline stays quiet: that is a normal way to start
#    SketchUp, not a fault. Every attempt is appended to
#    ~/Library/Application Support/mcft-ocl-update.log either way.
cat > "$PLUG/!mcft_autoupdate.rb" <<RUBY
# MCFT auto-update — written by dev-install-mac.sh; safe to delete to opt out.
require 'json'
require 'net/http'

# THE CI GATE. Returns [verdict, detail] for a commit:
#   :success  — MCFT checks passed; safe to fast-forward onto
#   :failure  — it went red. This is the case that matters: a red commit
#               reached this Mac on 2026-09-03 and its feature could not
#               appear, because the bundle it shipped was stale and CI had
#               said so an hour earlier.
#   :pending  — still running, or no run yet. Not a fault; just not yet.
#   :unknown  — the API could not be reached or read.
#
# :pending and :unknown both REFUSE. Loading code nobody has verified is the
# thing this exists to prevent, and "we could not check" is not "it is fine".
# Refusing costs one restart; the alternative cost half a day.
MCFT_CI_VERDICT = lambda do |sha|
  uri = URI("https://api.github.com/repos/malletcraft/mcft-opencutlist-sketchup-extension/actions/runs?head_sha=#{sha}&per_page=10")
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 6, read_timeout: 8) do |http|
    http.get(uri.request_uri, 'Accept' => 'application/vnd.github+json',
                              'User-Agent' => 'mcft-autoupdate')
  end
  return [:unknown, "GitHub API HTTP #{res.code}"] unless res.code.to_i == 200

  runs = JSON.parse(res.body)['workflow_runs'] || []
  checks = runs.select { |r| r['name'].to_s.start_with?('MCFT checks') }
  return [:pending, 'no MCFT checks run for this commit yet'] if checks.empty?

  run = checks.first
  return [:pending, "MCFT checks #{run['status']}"] unless run['status'] == 'completed'
  return [:success, run['html_url'].to_s] if run['conclusion'] == 'success'

  [:failure, "#{run['conclusion']} — #{run['html_url']}"]
rescue StandardError => e
  [:unknown, e.message]
end

begin
  repo = '$REPO'
  if File.directory?(File.join(repo, '.git'))
    # GUI SketchUp gets the bare launchd PATH; make sure git resolves.
    ENV['PATH'] = "#{ENV['PATH']}:/usr/bin:/opt/homebrew/bin:/usr/local/bin"
    git = lambda { |args| \`git -C "#{repo}" #{args} 2>&1\` }

    # FETCH FIRST, then decide. The old one-shot pull merged before anything
    # could object; splitting it is what makes a gate possible at all.
    out = git.call('-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 fetch origin mcft')
    ok = \$?.success?
    rev = git.call('log -1 --format=%h').strip

    if ok
      target = git.call('rev-parse origin/mcft').strip
      here   = git.call('rev-parse HEAD').strip

      if target == here
        # Nothing new. Say so and stop; no CI call, no rate limit spent.
        out = 'Already up to date.'
      else
        verdict, detail = MCFT_CI_VERDICT.call(target)
        if verdict == :success
          out = git.call('merge --ff-only origin/mcft')
          ok = \$?.success?
          rev = git.call('log -1 --format=%h').strip
        else
          ok = false
          # NOT a git failure, and it must not be reported as one. This is the
          # gate doing its job, and the person needs to know the difference
          # between "your clone is broken" and "that commit is not fit to run".
          out = "MCFT_CI_BLOCKED #{verdict} #{target[0, 9]} #{detail}"
        end
      end
    end
    begin
      log = File.expand_path('~/Library/Application Support/mcft-ocl-update.log')
      File.open(log, 'a') { |f| f.puts "#{Time.now} ok=#{ok} rev=#{rev} #{out.lines.last.to_s.strip}" }
    rescue StandardError
    end
    if ok
      puts "[MCFT] OpenCutList (MCFT Edition) up to date @ #{rev}"
    else
      reason = out.lines.last.to_s.strip

      if reason.start_with?('MCFT_CI_BLOCKED')
        # HELD BACK, not broken — and the wording has to say which, or the
        # next person "fixes" it with a manual git pull and defeats the gate.
        _, verdict, short, *rest = reason.split(' ')
        detail = rest.join(' ')
        puts "[MCFT] update HELD at #{rev}: #{short} is #{verdict} — #{detail}"
        if verdict == 'failure'
          UI.messagebox("MCFT plugin update HELD BACK.\n\n" \
                        "Still running #{rev}, which is fine.\n\n" \
                        "The newer commit #{short} FAILED its checks:\n#{detail}\n\n" \
                        "This is the guard working. Do not pull it by hand — " \
                        "wait for a green commit.")
        end
      else
        puts "[MCFT] update FAILED @ #{rev}: #{reason}"
        offline = reason =~ /resolve host|unable to access|timed out|network is unreachable|no route to host/i
        unless offline
          UI.messagebox("MCFT plugin update FAILED — still running #{rev}.\n\n" \
                        "#{reason}\n\n" \
                        "Fix in Terminal:\n  cd #{repo} && git pull\nthen restart SketchUp.")
        end
      end
    end
  end
rescue StandardError => e
  puts "[MCFT] update skipped (#{e.message})"
end
RUBY

echo "Linked + auto-update installed. Restart SketchUp — Extension Manager"
echo "should show:  OpenCutList (MCFT Edition)"
echo "From now on the ONLY update step is: restart SketchUp."
