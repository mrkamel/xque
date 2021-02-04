require_relative "lib/xque/version"

Gem::Specification.new do |spec|
  spec.name          = "xque"
  spec.version       = XQue::VERSION
  spec.authors       = ["Benjamin Vetter"]
  spec.email         = ["benjamin.vetter@wlw.de"]

  spec.summary       = "A reliable, redis-based job queue"
  spec.description   = "A reliable, redis-based job queue with automatic retries, backoff and job ttl's"
  spec.homepage      = "https://github.com/mrkamel/xque"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mrkamel/xque"
  spec.metadata["changelog_uri"] = "https://github.com/mrkamel/xque/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "timecop"

  spec.add_dependency "redis"
end
