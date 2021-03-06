# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'optica/client/version'

Gem::Specification.new do |spec|
  spec.name          = "optica-client"
  spec.version       = Optica::Client::VERSION
  spec.authors       = ["Jake Teton-Landis"]
  spec.email         = ["jake.tl@airbnb.com"]

  spec.summary       = %q{An Optica client}
  spec.description   = %q{An efficient Optica CLI client and accompanying Ruby library}
  spec.homepage      = "https://github.com/justjake/optica-client"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "https://rubygems.org"
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "filecache", "~> 1.0.2"

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "pry-doc"
end
