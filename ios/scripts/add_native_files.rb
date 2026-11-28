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

# Firebase config (ios/Runner/GoogleService-Info.plist) goes in the app bundle as a resource.
runner_group = project.main_group.children.find { |g| g.display_name == 'Runner' }
if runner_group && File.exist?('ios/Runner/GoogleService-Info.plist') &&
   runner_group.files.none? { |f| f.display_name == 'GoogleService-Info.plist' }
  runner.add_resources([runner_group.new_reference('GoogleService-Info.plist')])
end

(project.build_configurations + runner.build_configurations).each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
end
# Same bundle id as the Firebase iOS app and the store listing (flutter create makes com.zadx.zadx).
runner.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zadx.app'
end
project.save
puts 'Added AppLockPlugin.swift + SharedStore.swift to Runner; iOS 16.0; bundle id com.zadx.app; Firebase plist'
