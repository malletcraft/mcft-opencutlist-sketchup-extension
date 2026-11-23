#!/usr/bin/env ruby
# frozen_string_literal: true
# OPENCUTLIST'S OWN UPGRADE IS REFUSED, FIRST, BEFORE ANYTHING IS DOWNLOADED.
#
# On OpenCutList 8 a click on Upgrade sends core_upgrade, which reaches
# PLUGIN.upgrade_command -> Updater.new(PLUGIN_DIR, backup: IS_RBZ, ...) ->
# download_and_install -> Sketchup.install_from_archive. Through MOP's
# symlinks that replaces MOP with stock 8 — the estimate gone, and the clone
# possibly written through (docs/mcft/MOP-ON-OCL8.md §6.3). MOP updates when
# SketchUp restarts, behind a CI gate; this button must never run.
#
# 7.1 MOP carried the same refusal and NOTHING checked it. Asserted here:
#   1. upgrade_command's first statement is a UI.messagebox and its second
#      returns { :cancelled => true } — before Updater.new;
#   2. outside ruby/updater/ (which defines them) and ruby/lib/, nothing calls
#      download_and_install or install_from_archive except the dead code
#      under that return;
#   3. the only other Updater use is setup()'s discard_backup, which only
#      deletes *.upgrade_backup leftovers.
require_relative 'mcft_ruby_source'

RUBY = File.expand_path('../src/ladb_opencutlist/ruby', __dir__)
problems = []
lines = McftRubySource.lines
body = McftRubySource.method_body(lines, 'upgrade_command')
code = McftRubySource.code_lines(body[1..-2])

problems << "upgrade_command's first statement is not a UI.messagebox: #{code[0].inspect}" unless code[0].to_s.start_with?('UI.messagebox(')
unless code[1].to_s =~ /\Areturn\s*\{\s*(?::cancelled\s*=>|cancelled:)\s*true\s*\}\z/
  problems << "upgrade_command's second statement does not return { cancelled: true }: #{code[1].inspect}"
end
refusal_at = code.index { |l| l =~ /\Areturn\s*\{.*cancelled/ } || 0
first_updater = code.index { |l| l.include?('Updater.new') }
problems << 'upgrade_command reaches Updater.new before refusing' if first_updater && first_updater < refusal_at

upgrade_range = McftRubySource.methods_of(lines).find { |n, _, _| n == 'upgrade_command' }
Dir[File.join(RUBY, '**', '*.rb')].sort.each do |f|
  rel = f.sub("#{RUBY}/", '')
  next if rel.start_with?('lib/', 'updater/')
  File.readlines(f, encoding: 'UTF-8').each_with_index do |l, i|
    next if l.strip.start_with?('#')
    in_upgrade = rel == 'plugin.rb' && i > upgrade_range[1] && i <= upgrade_range[2]
    if l =~ /\b(download_and_install|install_from_archive)\b/ && !in_upgrade
      problems << "#{rel}:#{i + 1} calls #{$1} outside upgrade_command"
    end
    next unless l =~ /\bUpdater\.new\b/ && !in_upgrade
    following = File.readlines(f, encoding: 'UTF-8')[i + 1, 2].join
    problems << "#{rel}:#{i + 1} uses Updater for something other than discard_backup" unless following.include?('.discard_backup')
  end
end

unless problems.empty?
  problems.each { |p| warn "check-upgrade-refused: #{p}" }
  abort "check-upgrade-refused: #{problems.size} problem(s) — OpenCutList's Upgrade could replace MOP"
end
puts "check-upgrade-refused: upgrade_command refuses first (#{code[0][0, 40]}...), and nothing else installs an rbz"
