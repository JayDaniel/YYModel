Pod::Spec.new do |s|
  s.name         = 'YYModel'
  s.summary      = 'High performance model framework for iOS/OSX.'
  s.version      = '1.0.4'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'ibireme' => 'ibireme@gmail.com' }
  s.social_media_url = 'http://blog.ibireme.com'
  s.homepage     = 'https://github.com/ibireme/YYModel'

  s.ios.deployment_target = '14.0'

  s.source       = { :git => 'https://github.com/ibireme/YYModel.git', :tag => s.version.to_s }
  
  s.requires_arc = true
  s.source_files = 'YYModel/*.{h,m}'
  s.public_header_files = 'YYModel/*.{h}'
  s.resources = 'YYModel/PrivacyInfo.xcprivacy'
  
  s.frameworks = 'Foundation', 'CoreFoundation'

end
