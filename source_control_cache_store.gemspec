# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "source_control_cache_store"
  spec.version       = "0.1.0"
  spec.authors       = ["Unsupervised.com"]
  spec.email         = ["noah@unsupervised.com"]

  spec.summary       = "Rails cache store appropriate for storing the results in source control"
  spec.description   = "A Rails cache store that stores cache entries as files suitable for version control"
  spec.homepage      = "https://github.com/Unsupervisedcom/source_control_cache_store"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.1.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
