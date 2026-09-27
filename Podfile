platform :ios, '17.0'

target 'FormBuddy' do
  use_frameworks!
  pod 'MediaPipeTasksVision', '1.0.0'

  target 'FormBuddyTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  # MediaPipeTasksCommon's podspec sets a `user_target_xcconfig` that
  # `-force_load`s its static graph library. CocoaPods applies that to the test
  # target too, duplicating every ObjC class already linked into the host app;
  # those duplicates crash XCTest bundle injection before any test runs. Strip
  # it from the test target's generated xcconfig — the host app still links it,
  # and the test bundle loads it from the app at runtime.
  test_support = File.join(installer.sandbox.target_support_files_root, 'Pods-FormBuddyTests')
  Dir.glob(File.join(test_support, '*.xcconfig')).each do |path|
    contents = File.read(path)
    scrubbed = contents.gsub(/^OTHER_LDFLAGS\[sdk=[^\]]+\] = .*force_load.*$\n?/, '')
    File.write(path, scrubbed) unless scrubbed == contents
  end
end
