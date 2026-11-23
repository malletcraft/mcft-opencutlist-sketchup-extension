#!/usr/bin/env ruby
# frozen_string_literal: true
# ONE UPSTREAM BUILD, NAMED THE SAME IN EVERY PLACE THAT NAMES IT — AND A
# VERSION THAT DOES NOT TURN 8's LAB MODE ON.
#
# The dialog's JS comes from dist/ladb_opencutlist.rbz (common-bundle.js
# carries js/constants.js with the rbz's EXTENSION_BUILD). When the Ruby's
# build differs, the dialog locks itself into upstream's "zzz" layout
# (8 jquery.ladb.dialog-tabs.js 801-816). So the rbz's ruby/constants.rb,
# src's constants.rb and dist/manifest.json must all name one build
# (docs/mcft/MOP-ON-OCL8.md §2.3, §7.3 check 2).
#
# And the version: 8 sets IS_LAB = EXTENSION_VERSION =~ /-[a-z]+\z/. IS_LAB
# clears the Ruby Console at start (plugin.rb, SKETCHUP_CONSOLE.clear if
# IS_LAB), which would wipe the "[MCFT] ... up to date @ <rev>" line printed
# just before it, and shows the orange Upgrade dot every LAB week. MOP's
# version ends in a digit; the loader's ex.version says the same.
require 'json'
require 'open3'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)
build_of = ->(src) { (m = src.to_s.match(/EXTENSION_BUILD\s*=\s*'([^']+)'/)) ? m[1] : nil }

rbz_const, err, st = Open3.capture3('unzip', '-p', 'dist/ladb_opencutlist.rbz',
                                    'ladb_opencutlist/ruby/constants.rb')
abort "check-build-matches-rbz: cannot read the rbz's constants.rb: #{err.strip}" unless st.success? && !rbz_const.empty?
src_const = File.read('src/ladb_opencutlist/ruby/constants.rb', encoding: 'UTF-8')
manifest = JSON.parse(File.read('dist/manifest.json'))
loader = File.read('src/ladb_opencutlist.rb', encoding: 'UTF-8')

builds = { 'the rbz' => build_of.call(rbz_const.force_encoding('UTF-8')),
           'src constants.rb' => build_of.call(src_const),
           'dist/manifest.json' => manifest['build'].to_s }
version = (m = src_const.match(/EXTENSION_VERSION\s*=\s*'([^']+)'/)) ? m[1] : nil
ex_version = (m = loader.match(/ex\.version\s*=\s*"([^"]+)"/)) ? m[1] : nil

problems = []
problems << "EXTENSION_BUILD differs: #{builds.map { |k, v| "#{k}=#{v.inspect}" }.join(', ')}" if builds.values.uniq.size != 1 || builds.values.first.to_s.empty?
problems << 'EXTENSION_VERSION not found in constants.rb' unless version
problems << "EXTENSION_VERSION #{version.inspect} matches /-[a-z]+\\z/, so IS_LAB would be true" if version && version =~ /-[a-z]+\z/
problems << "the loader's ex.version #{ex_version.inspect} is not EXTENSION_VERSION #{version.inspect}" if ex_version != version

unless problems.empty?
  problems.each { |p| warn "check-build-matches-rbz: #{p}" }
  abort "check-build-matches-rbz: #{problems.size} problem(s)"
end
puts "check-build-matches-rbz: build #{builds.values.first} in the rbz, src and manifest; version #{version} (IS_LAB false)"
