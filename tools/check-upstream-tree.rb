#!/usr/bin/env ruby
# frozen_string_literal: true
# EVERY PATH THAT IS NOT MCFT'S IS THE UPSTREAM BUILD'S, BYTE FOR BYTE.
#
# docs/mcft/MOP-ON-OCL8.md §7.3 check 6. On this line an upstream move is a
# `git merge -s ours` that records ancestry, plus tools/mcft-take-upstream.sh,
# which makes the tree from the build named in docs/mcft/UPSTREAM. A merge
# whose content git decided would be wrong in a way no conflict reports: git's
# merge base here is a virtual one, and after a go-back commit it is the bad
# build, so its changes would be silently kept out of the next merge. This is
# what proves, on every push, that no such merge got in.
#
# Asserted:
#   - every HEAD (or, with --index, staged) path outside MCFT-PATHS has the build's mode and object id
#     (equal ids are equal bytes, so no blob is downloaded);
#   - every build path outside MCFT-PATHS exists at HEAD (nothing missing);
#   - every own: path exists at HEAD and not at the build, every changed:
#     path exists at both;
#   - the build's own EXTENSION_BUILD equals HEAD's, so a build commit whose
#     sources are newer than its rbz (a mid-week commit) cannot be named.
#
# The build is fetched trees-only when this checkout lacks it (CI's shallow
# checkout does): a promisor remote, --depth=1 --filter=blob:none, ~50 KiB.
require 'open3'
# git's output is UTF-8; a CI runner or a bare shell may default to US-ASCII.
Encoding.default_external = Encoding::UTF_8
require_relative 'mcft_paths'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)
UPSTREAM_URL = 'https://github.com/lairdubois/lairdubois-opencutlist-sketchup-extension.git'
REMOTE = 'mcft-upstream-check'
CONSTANTS = 'src/ladb_opencutlist/ruby/constants.rb'

def git(*args)
  out, err, st = Open3.capture3('git', *args)
  [out, err, st.success?]
end

def die(msg)
  warn "check-upstream-tree: #{msg}"
  exit 1
end

sha = File.read('docs/mcft/UPSTREAM').strip
die "docs/mcft/UPSTREAM is not a full sha: #{sha.inspect}" unless sha =~ /\A\h{40}\z/
list = McftPaths.load(ROOT)

_, _, have = git('cat-file', '-e', "#{sha}^{tree}")
unless have
  remotes, = git('remote')
  unless remotes.split("\n").include?(REMOTE)
    git('remote', 'add', REMOTE, UPSTREAM_URL)
    git('config', "remote.#{REMOTE}.promisor", 'true')
    git('config', "remote.#{REMOTE}.partialclonefilter", 'blob:none')
  end
  _, err, ok = git('fetch', '-q', '--depth=1', '--filter=blob:none', REMOTE, sha)
  die "could not fetch the upstream build #{sha[0, 9]}: #{err.strip}" unless ok
end

def tree(rev)
  out, err, ok = git('ls-tree', '-r', '-z', '--full-tree', rev)
  die "git ls-tree #{rev}: #{err.strip}" unless ok
  out.split("\0").each_with_object({}) do |entry, h|
    meta, path = entry.split("\t", 2)
    mode, type, oid = meta.split(' ')
    h[path] = [mode, type, oid]
  end
end

# --index checks what is STAGED (before `git commit` of a merge), not HEAD.
here = 'HEAD'
if ARGV.include?('--index')
  out, err, ok = git('write-tree')
  die "git write-tree: #{err.strip} (unresolved conflicts?)" unless ok
  here = out.strip
end
head = tree(here)
build = tree(sha)
problems = []

head.each do |path, entry|
  next if list.mcft?(path)
  if !build.key?(path)
    problems << "#{path}: not in the build and not listed in MCFT-PATHS"
  elsif build[path] != entry
    problems << "#{path}: differs from the build (#{entry[2][0, 9]} here, #{build[path][2][0, 9]} there)"
  end
end
build.each_key do |path|
  next if list.mcft?(path) || head.key?(path)
  problems << "#{path}: in the build but missing here"
end

list.own.each do |own|
  if own.end_with?('/')
    problems << "own: #{own} has no file at HEAD" unless head.keys.any? { |p| p.start_with?(own) }
    problems << "own: #{own} exists in the build" if build.keys.any? { |p| p.start_with?(own) }
  else
    problems << "own: #{own} is not at HEAD" unless head.key?(own)
    problems << "own: #{own} exists in the build" if build.key?(own)
  end
end
list.changed.each do |c|
  problems << "changed: #{c} is not at HEAD" unless head.key?(c)
  problems << "changed: #{c} is not in the build" unless build.key?(c)
end

build_const = lambda do |rev|
  src, err, ok = git('show', "#{rev}:#{CONSTANTS}")
  die "git show #{rev[0, 9]}:#{CONSTANTS}: #{err.strip}" unless ok
  (m = src.match(/EXTENSION_BUILD\s*=\s*'([^']+)'/)) ? m[1] : nil
end
theirs = build_const.call(sha)
ours = build_const.call(here)
unless theirs && theirs == ours
  problems << "EXTENSION_BUILD is #{ours.inspect} here and #{theirs.inspect} in the build #{sha[0, 9]}"
end

unless problems.empty?
  shown = problems.first(25)
  shown.each { |p| warn "check-upstream-tree: #{p}" }
  warn "check-upstream-tree: ... and #{problems.size - shown.size} more" if problems.size > shown.size
  die "#{problems.size} problem(s): the tree is not build #{sha[0, 9]} plus MCFT " \
      '(make it with tools/mcft-take-upstream.sh; list MCFT paths in docs/mcft/MCFT-PATHS)'
end
n_up = head.keys.count { |p| !list.mcft?(p) }
puts "check-upstream-tree: #{n_up} upstream path(s) equal build #{sha[0, 9]} (EXTENSION_BUILD #{ours}); " \
     "#{head.size - n_up} MCFT path(s), #{list.own.size} own: and #{list.changed.size} changed: entries"
