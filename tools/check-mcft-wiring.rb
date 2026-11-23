#!/usr/bin/env ruby
# frozen_string_literal: true
# MCFTCONTROLLER IS REQUIRED BEFORE IT IS NAMED, AND IT IS STARTED.
#
# OpenCutList 8 moved the controllers' require_relative lines from the top of
# plugin.rb into start(), which runs on first dialog open. setup() runs at
# LOAD and builds the menu — MOP's hunk there names McftController — so
# without its own require that line is a NameError that stops the whole
# extension. check-requires.rb passed on exactly that tree: it proves every
# require points at a file, not that a constant is loaded before use
# (docs/mcft/MOP-ON-OCL8.md §7.3 check 3).
#
# Asserted, from the source: every method in plugin.rb that names
# McftController has `require_relative 'controller/mcft_controller'` earlier
# in the same method, or at file level before the method; and start() pushes
# McftController.new onto @controllers.
require_relative 'mcft_ruby_source'

REQ = /\A\s*require_relative\s+['"]controller\/mcft_controller['"]/
lines = McftRubySource.lines
methods = McftRubySource.methods_of(lines)
problems = []
named = 0

methods.each do |name, from, to|
  (from..to).each do |i|
    l = lines[i]
    next if l.strip.start_with?('#') || l !~ /\bMcftController\b/
    named += 1
    in_method = (from...i).any? { |k| lines[k] =~ REQ }
    at_file = (0...from).any? { |k| lines[k] =~ REQ && methods.none? { |_, f, t| k > f && k <= t } }
    next if in_method || at_file
    problems << "plugin.rb:#{i + 1} (#{name}) names McftController with no require_relative " \
                "'controller/mcft_controller' before it"
  end
end
start = McftRubySource.method_body(lines, 'start')
problems << 'start() does not push McftController.new onto @controllers' unless start.any? { |l| l =~ /@controllers\.push\(McftController\.new\)/ }
problems << 'plugin.rb never names McftController' if named.zero?

unless problems.empty?
  problems.each { |p| warn "check-mcft-wiring: #{p}" }
  abort "check-mcft-wiring: #{problems.size} problem(s) — a NameError here stops the whole extension at load"
end
puts "check-mcft-wiring: #{named} use(s) of McftController in plugin.rb, each required first; start() pushes it"
