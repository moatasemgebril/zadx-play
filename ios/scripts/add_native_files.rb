# Adds Zad X's native Swift files to the Runner target after `flutter create`
# and raises the deployment target to iOS 16 (needed by FamilyControls).
# Usage (from the project root): ruby ios/scripts/add_native_files.rb
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'Runner target not found'

def add_file(project, target, group_path, file_name)
  group = project.main_group.children.find { |g| g.display_name == group_path } ||
          project.main_group.new_group(group_path, group_path)
  return if group.files.any? { |f| f.display_name == file_name }
  ref = group.new_reference(file_name)
  target.add_file_references([ref])
end

add_file(project, runner, 'Runner', 'AppLockPlugin.swift')
add_file(project, runner, 'Shared', 'SharedStore.swift')

(project.build_configurations + runner.build_configurations).each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
end
project.save
puts 'Added AppLockPlugin.swift + SharedStore.swift to Runner; iOS 16.0'
