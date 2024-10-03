require_relative "lib/glue_gun/version"

Gem::Specification.new do |spec|
  spec.name          = "glue_gun_dsl"
  spec.version       = "0.1.0"
  spec.authors       = ["Brett Shollenberger"]
  spec.email         = ["brett.shollenberger@gmail.com"]

  spec.summary       = "GlueGun extends ActiveModel for dependency management"
  spec.description   = "GlueGun makes dependency injection and hydration a first-order concern"
  spec.homepage      = "https://github.com/brettshollenberger/glue_gun_dsl"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb"]
  spec.required_ruby_version = ">= 2.5"

  spec.add_dependency "activemodel", ">= 5.2", "< 8"
  spec.add_dependency "activesupport", ">= 5.2", "< 8"

  # Optional: Add development dependencies
  spec.add_development_dependency "ostruct"
  spec.add_development_dependency "polars-df"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec", "~> 3.0"
end
