Pod::Spec.new do |s|
  s.name = 'GoogleUtilitiesComponents'
  s.version = '1.1.0'
  s.summary = 'Google Utilities Component Container for Apple platforms.'
  s.description = 'An internal Google utility that is a dependency injection system.'
  s.homepage = 'https://developers.google.com/'
  s.license = { :type => 'Apache', :file => 'LICENSE' }
  s.authors = 'Google, Inc.'
  s.source = { :path => '.' }
  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.12'
  s.tvos.deployment_target = '10.0'
  s.prefix_header_file = false
  s.static_framework = true
  s.source_files = 'Sources/**/*.[mh]'
  s.public_header_files = ['Sources/Public/*.h', 'Sources/Private/*.h']
  s.private_header_files = 'Sources/Private/*.h'
  s.dependency 'GoogleUtilities/Logger'
end
