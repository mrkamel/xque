require "xque"

ENV["REDIS_URL"] ||= "redis://localhost:6379/0"

RedisClient = Redis.new(url: ENV.fetch("REDIS_URL"))

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    RedisClient.flushdb
  end
end
