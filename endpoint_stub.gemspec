# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'endpoint_stub/version'

Gem::Specification.new do |spec|
  spec.name          = "endpoint_stub"
  spec.version       = EndpointStub::VERSION
  spec.authors       = ["Nigel Baillie"]
  spec.email         = ["metreckk@gmail.com"]
  spec.summary       = %q{Uses WebMock to intercept http requests for basic CRUD operations with ActiveResource.}
  spec.description   = %q{
    Kind of like the built-in HttpMock that ActiveResource comes with, except EntpointStub
    actually creates and destroys models, and also allows you to bind custom logic to a
    particular path. Kind of like a controller.
  }
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "activeresource"
  spec.add_development_dependency "webmock"

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
