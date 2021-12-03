#
# Be sure to run `pod lib lint FYVideoCompressorpodspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'FYVideoCompressor'
  s.version          = '0.0.1'
  s.summary          = 'A high-performance, flexible and easy to use Video compressor library written by Swift.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
  A high-performance, flexible and easy to use Video compressor library written by Swift. Using hardware-accelerator APIs in AVFoundation.
  DESC

  s.homepage         = 'https://github.com/T2Je'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 't2je' => '827034457@qq.com' }
  s.source           = { :git => 'https://github.com/T2Je/FYVideoCompressor.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

   s.ios.deployment_target = '11'
   s.swift_version = '5'

   s.source_files = 'Sources/FYVideoCompressor/**/*'

   s.frameworks = 'AVFoundation'

end

