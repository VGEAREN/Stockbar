#!/usr/bin/env ruby
# Adds Swift source files to the Xcode project (StockMonitor + StockMonitorTests targets)
# Usage: ruby add_files.rb <relative_file_path> [<relative_file_path> ...]
#   Path examples:
#     StockMonitor/Models/Stock.swift        → added to StockMonitor target
#     StockMonitorTests/Models/StockTests.swift → added to StockMonitorTests target

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../StockMonitor.xcodeproj', __FILE__)
proj = Xcodeproj::Project.open(PROJECT_PATH)

app_target  = proj.targets.find { |t| t.name == 'StockMonitor' }
test_target = proj.targets.find { |t| t.name == 'StockMonitorTests' }

def find_or_create_group(parent, name)
  parent.groups.find { |g| g.display_name == name } ||
    parent.new_group(name, name)
end

ARGV.each do |rel_path|
  abs_path = File.expand_path(rel_path, __dir__)
  unless File.exist?(abs_path)
    warn "File not found: #{abs_path}"
    next
  end

  parts      = rel_path.split('/')            # e.g. ["StockMonitor","Models","Stock.swift"]
  top_folder = parts[0]                       # "StockMonitor" or "StockMonitorTests"
  sub_groups = parts[1..-2]                   # ["Models"]
  file_name  = parts[-1]                      # "Stock.swift"

  # Resolve top-level group in the project
  top_group = proj.main_group.groups.find { |g| g.display_name == top_folder }
  unless top_group
    warn "Top-level group '#{top_folder}' not found in project"
    next
  end

  # Walk/create sub-groups
  group = top_group
  sub_groups.each { |sg| group = find_or_create_group(group, sg) }

  # Skip if file reference already exists
  if group.files.any? { |f| f.display_name == file_name }
    puts "Already in project: #{rel_path}"
    next
  end

  file_ref = group.new_reference(abs_path)

  target = top_folder == 'StockMonitor' ? app_target : test_target
  target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{rel_path}"
end

proj.save
puts "Project saved."
