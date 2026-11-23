# frozen_string_literal: true
# ---------------------------------------------------------------------------
# MCFT AUTO-UPDATE — "restart SketchUp" IS the update (docs/mcft/MOP-ON-OCL8.md
# §6.2).
#
# Loaded FROM THE CLONE on every SketchUp start by the stub that
# tools/dev-install-mac.sh writes into Plugins as !mcft_autoupdate.rb (the "!"
# makes SketchUp load it before OpenCutList). Living here, it reaches the Mac
# with the code it updates, never needing a re-install — the S4 MDT pattern
# (dev/load_from_checkout.rb). The code that runs is HEAD's, and HEAD has
# already passed the CI gate below.
#
# In order:
#   1. INTEGRITY FIRST, before the fetch: tools/mcft-refresh-outputs.sh
#      --verify. A tracked file changed (10) or an output no longer matching
#      its stamp (12) means something wrote INTO the clone — an .rbz install
#      or OpenCutList's Upgrade, through the links. Then: no fetch, no
#      fast-forward, no refresh, a loud message, and NEVER "up to date".
#      A missing stamp on a clean tree (11) is an interrupted refresh: run the
#      full refresh and carry on.
#   2. fetch, the CI gate, `merge --ff-only` — the gate refuses red, pending
#      and "could not check" alike.
#   3. tools/mcft-refresh-outputs.sh --if-stale, before OpenCutList loads.
#   4. a refresh that failed before touching src/ (20): `git reset --keep`
#      to the HEAD before the fast-forward, so the source matches the outputs
#      still on disk; "held at <rev>". After touching src/ (21): one command.
#   5. what will actually load: Plugins/ladb_opencutlist and
#      ladb_opencutlist.rb must be symlinks resolving into this clone.
#   6. the startup line and one log line.
#
# Every failure names the install script, never `git pull`: a hand pull
# bypasses the CI gate and the output refresh both.
# ---------------------------------------------------------------------------
require 'json'
require 'net/http'
require 'open3'

module McftAutoupdate

  REPO_API = 'https://api.github.com/repos/malletcraft/mcft-opencutlist-sketchup-extension'
  LOG = File.expand_path('~/Library/Application Support/mcft-ocl-update.log')

  # -- Pure decisions: tools/check-autoupdate.rb runs these without SketchUp.

  # What to do after `mcft-refresh-outputs.sh --verify` exits with `code`.
  def self.after_verify(code)
    case code
    when 0 then :ok
    when 11 then :refresh        # an interrupted refresh: heal it
    when 10, 12 then :modified   # something wrote into the clone
    else :broken                 # the script itself failed to run
    end
  end

  # What to do after a refresh (full or --if-stale) exits with `code`.
  def self.after_refresh(code)
    case code
    when 0 then :ok
    when 20 then :hold     # nothing under src/ touched: put the old HEAD back
    else :reinstall        # 21, or anything else: src/ may be half-written
    end
  end

  # The CI verdict from a GitHub "list workflow runs for a sha" response body.
  #   :success — MCFT checks passed; safe to fast-forward onto
  #   :failure — it went red (a red commit reached this Mac on 2026-09-03)
  #   :pending — still running, or no run yet
  # The caller maps a request that could not be made to :unknown. :pending and
  # :unknown both REFUSE: "we could not check" is not "it is fine".
  def self.ci_verdict_from(body)
    runs = JSON.parse(body)['workflow_runs'] || []
    checks = runs.select { |r| r['name'].to_s.start_with?('MCFT checks') }
    return [:pending, 'no MCFT checks run for this commit yet'] if checks.empty?
    run = checks.first
    return [:pending, "MCFT checks #{run['status']}"] unless run['status'] == 'completed'
    return [:success, run['html_url'].to_s] if run['conclusion'] == 'success'
    [:failure, "#{run['conclusion']} — #{run['html_url']}"]
  end

  # Plugins entries that are not this clone's, by name. `link` answers
  # [symlink?, realpath-or-nil] for a path; injected so the rule is testable.
  # BOTH sides are compared resolved: `real` has every symlink resolved, and
  # the clone's path is the installer's unresolved `pwd`, so a clone reached
  # through a symlinked folder (~/dev -> elsewhere) would otherwise read as
  # "not MOP" on every start (the review, docs/mcft/MOP-ON-OCL8.md §12).
  def self.foreign_plugins(repo_src, link)
    { 'ladb_opencutlist' => File.join(repo_src, 'ladb_opencutlist'),
      'ladb_opencutlist.rb' => File.join(repo_src, 'ladb_opencutlist.rb') }.reject do |name, want|
      is_link, real = link.call(name)
      want_real = (File.realpath(want) rescue want)
      is_link && real == want_real
    end.keys
  end

  # The stall guard for every git call that can download: the fetch, AND the
  # fast-forward — on the --filter=blob:none clone the merge's checkout is what
  # fetches the new blobs (the 22.5 MB rbz among them), through a promisor
  # fetch that inherits these -c settings. A stalled link fails in 10 s instead
  # of hanging the SketchUp start.
  NET = '-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10'

  def self.install_command(repo)
    "bash #{repo}/tools/dev-install-mac.sh"
  end

  # -- The run, in SketchUp.

  def self.run(repo, plugins_dir)
    # GUI SketchUp gets the bare launchd PATH; make sure git resolves.
    ENV['PATH'] = "#{ENV['PATH']}:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
    @repo = repo
    refresh = File.join(repo, 'tools', 'mcft-refresh-outputs.sh')
    rev = _git('log -1 --format=%h').first.strip
    outputs = -> { (File.readlines(File.join(repo, 'src', 'ladb_opencutlist', '.mcft-outputs')).first || '').strip[0, 9] rescue 'none' }

    # 1. Integrity, before anything moves.
    out, code = _sh('bash', refresh, '--verify')
    case after_verify(code)
    when :modified
      _log(false, rev, "clone-modified #{code}", outputs.call)
      puts "[MCFT] OpenCutList (MCFT Edition) NOT verified @ #{rev}: the clone was modified (#{code})"
      UI.messagebox("MCFT: something replaced MOP's files in\n#{repo}\n\n#{out.lines.first(3).join}\n" \
                    "MOP was NOT updated, and what loads now may not be MOP.\n\n" \
                    "Quit SketchUp and run:\n  #{install_command(repo)}")
      return
    when :refresh
      rout, rcode = _sh('bash', refresh)
      unless after_refresh(rcode) == :ok
        _log(false, rev, "outputs-missing refresh=#{rcode}", outputs.call)
        UI.messagebox("MCFT: MOP's build outputs are missing and could not be laid down.\n\n" \
                      "#{rout.lines.last(2).join}\nQuit SketchUp and run:\n  #{install_command(repo)}")
        return
      end
    when :broken
      _log(false, rev, "verify-broken #{code}", outputs.call)
      UI.messagebox("MCFT: the update check could not run (#{code}).\n\n#{out.lines.last(2).join}\n" \
                    "Quit SketchUp and run:\n  #{install_command(repo)}")
      return
    end

    # 2. Fetch, gate, fast-forward.
    ok = true
    note = 'Already up to date.'
    fout, fcode = _git("#{NET} fetch origin mcft")
    if fcode != 0
      ok = false
      note = fout.lines.last.to_s.strip
      offline = note =~ /resolve host|unable to access|timed out|network is unreachable|no route to host/i
      puts "[MCFT] update FAILED @ #{rev}: #{note}"
      unless offline
        UI.messagebox("MCFT plugin update FAILED — still running #{rev}.\n\n#{note}\n\n" \
                      "Quit SketchUp and run:\n  #{install_command(repo)}")
      end
    else
      target = _git('rev-parse origin/mcft').first.strip
      here = _git('rev-parse HEAD').first.strip
      if target != here
        verdict, detail = _ci_verdict(target)
        if verdict == :success
          mout, mcode = _git("#{NET} merge --ff-only origin/mcft")
          if mcode != 0
            ok = false
            note = mout.lines.last.to_s.strip
            UI.messagebox("MCFT plugin update FAILED — still running #{rev}.\n\n#{note}\n\n" \
                          "Quit SketchUp and run:\n  #{install_command(repo)}")
          else
            # 3. The outputs follow the source, before OpenCutList loads.
            rout, rcode = _sh('bash', refresh, '--if-stale')
            case after_refresh(rcode)
            when :ok
              rev = _git('log -1 --format=%h').first.strip
              note = "fast-forwarded to #{rev}"
            when :hold
              _git("reset --keep #{here}")
              ok = false
              note = "held at #{rev}: #{rout.lines.last.to_s.strip}"
              puts "[MCFT] update HELD at #{rev}: #{rout.lines.last.to_s.strip}"
              UI.messagebox("MCFT plugin update HELD at #{rev}, which is fine.\n\n" \
                            "#{target[0, 9]} could not lay down its build outputs:\n#{rout.lines.last}\n" \
                            'The next start tries again.')
            else
              ok = false
              note = "outputs half-written: #{rout.lines.last.to_s.strip}"
              UI.messagebox("MCFT: the update to #{target[0, 9]} could not finish laying down its build " \
                            "outputs.\n\n#{rout.lines.last}\nQuit SketchUp and run:\n  #{install_command(repo)}")
            end
          end
        else
          # HELD BACK, not broken — and the wording has to say which, or the
          # next person "fixes" it by hand and defeats the gate.
          ok = false
          note = "MCFT_CI_BLOCKED #{verdict} #{target[0, 9]} #{detail}"
          puts "[MCFT] update HELD at #{rev}: #{target[0, 9]} is #{verdict} — #{detail}"
          if verdict == :failure
            UI.messagebox("MCFT plugin update HELD BACK.\n\nStill running #{rev}, which is fine.\n\n" \
                          "The newer commit #{target[0, 9]} FAILED its checks:\n#{detail}\n\n" \
                          'This is the guard working. Do not update it by hand — wait for a green commit.')
          end
        end
      end
    end

    # 5. What will actually load.
    foreign = foreign_plugins(File.join(repo, 'src'), lambda { |name|
      p = File.join(plugins_dir, name)
      [File.symlink?(p), (File.realpath(p) rescue nil)]
    })
    unless foreign.empty?
      _log(false, rev, "plugins-not-mop #{foreign.join(',')}", outputs.call)
      puts "[MCFT] OpenCutList in Plugins is NOT MOP: #{foreign.join(', ')}"
      UI.messagebox("MCFT: OpenCutList in Plugins is not MOP — an .rbz install or OpenCutList's Upgrade " \
                    "replaced #{foreign.join(' and ')}.\n\nQuit SketchUp and run:\n  #{install_command(repo)}")
      return
    end

    # 6. Say it.
    puts "[MCFT] OpenCutList (MCFT Edition) up to date @ #{rev}" if ok
    _log(ok, rev, note, outputs.call)
  rescue StandardError => e
    puts "[MCFT] update skipped (#{e.message})"
    _log(false, rev || '?', "exception #{e.message}", 'unknown') rescue nil
  end

  def self._sh(*cmd)
    out, st = Open3.capture2e(*cmd)
    [out, st.exitstatus || 1]
  rescue StandardError => e
    [e.message, 127]
  end

  def self._git(args)
    out, st = Open3.capture2e("git -C \"#{@repo}\" #{args}")
    [out, st.exitstatus || 1]
  end

  def self._ci_verdict(sha)
    uri = URI("#{REPO_API}/actions/runs?head_sha=#{sha}&per_page=10")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 6, read_timeout: 8) do |http|
      http.get(uri.request_uri, 'Accept' => 'application/vnd.github+json', 'User-Agent' => 'mcft-autoupdate')
    end
    return [:unknown, "GitHub API HTTP #{res.code}"] unless res.code.to_i == 200
    ci_verdict_from(res.body)
  rescue StandardError => e
    [:unknown, e.message]
  end

  def self._log(ok, rev, note, outputs)
    File.open(LOG, 'a') { |f| f.puts "#{Time.now} ok=#{ok} rev=#{rev} outputs=#{outputs} #{note.to_s.lines.last.to_s.strip}" }
  rescue StandardError
    nil
  end

end
