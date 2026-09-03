#!/usr/bin/env ruby
# frozen_string_literal: true
#
# EVERY that.dialog.<method>() CALL MUST NAME A METHOD THAT EXISTS.
#
# `node --check` parses; it cannot know that dialog.stopProgress was never
# written. So on 2026-09-03 a batch feature shipped calling two invented
# methods — stopProgress and advanceProgress, where the real API is
# finishProgress and incProgress — and the only thing that found them was Amit
# clicking the button and getting a red TypeError.
#
# The dialog API is a small, closed set defined on two prototypes, so checking
# calls against it is cheap and exact. This is the plugin's substitute for the
# unit tests it does not have: it cannot prove behaviour, but it can prove that
# every method being called is real.
require 'set'

ROOT = File.expand_path('..', __dir__)

def prototype_methods(*files)
  names = Set.new
  files.each do |f|
    path = File.join(ROOT, f)
    next unless File.exist?(path)
    src = File.read(path, encoding: 'UTF-8')
    src.scan(/^\s*(?:Ladb\w+)\.prototype\.(\w+)\s*=/) { |m| names << m[0] }
    # `capabilities` and friends are plain properties, not methods; a call
    # site would be a different error and this check does not claim to find it.
    src.scan(/^\s*this\.(\w+)\s*=\s*function/) { |m| names << m[0] }
  end
  names
end

known = prototype_methods(
  'src/ladb_opencutlist/js/plugins/jquery.ladb.abstract-dialog.js',
  'src/ladb_opencutlist/js/plugins/jquery.ladb.dialog-tabs.js',
  'src/ladb_opencutlist/js/plugins/jquery.ladb.dialog-modal.js',
  'src/ladb_opencutlist/js/plugins/jquery.ladb.dialog.js'
)
abort('could not read the dialog prototypes — check the paths in this script') if known.size < 5

bad = []
Dir[File.join(ROOT, 'src/ladb_opencutlist/js/plugins/**/*.js')].sort.each do |path|
  next if path.include?('/lib/')
  File.read(path, encoding: 'UTF-8').each_line.with_index(1) do |line, no|
    line.scan(/\b(?:that|this)\.dialog\.(\w+)\s*\(/) do |m|
      name = m[0]
      next if known.include?(name)
      bad << [path.sub("#{ROOT}/", ''), no, name]
    end
  end
end

if bad.empty?
  puts "dialog API: every call names one of #{known.size} real methods"
  exit 0
end

bad.each do |file, no, name|
  warn "::error file=#{file},line=#{no}::dialog.#{name}() does not exist"
end
warn ''
warn "Known dialog methods: #{known.to_a.sort.join(', ')}"
exit 1
