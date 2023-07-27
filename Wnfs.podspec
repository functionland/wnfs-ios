Pod::Spec.new do |spec|
  spec.name         = "Wnfs"
  spec.version      = "1.0.1"
  spec.summary      = "A wrapper around the WNFS swift bindings."
  spec.description  = <<-DESC
  A wrapper around the WNFS swift bindings, supports ios 8.0+.
  DESC
  spec.homepage     = "http://github.com/functionland/wnfs-swift-package"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author             = { "Homayoun Heidarzadeh" => "hhio618@gmail.com" }
  spec.platform     = :ios, "13.0"
  spec.source = { :git => "https://github.com/functionland/wnfs-ios.git", :tag => "v#{spec.version}" }
  spec.source_files  = "Sources", "Sources/**/*.{h,m,swift}"
  spec.exclude_files = "Tests/"
  spec.dependency "WnfsBindings", '1.0.0'
  spec.static_framework = true
  spec.swift_version = "5.0"
end
