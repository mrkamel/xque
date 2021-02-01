# XQue

**A reliable, redis-based job queue**

XQue is a reliable, redis-based job queue with automatic retries, backoff and
job ttl's.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'xque'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install xque

## Usage

First, let's write a simple worker, which sends an email for email
verification after a user has signed up in a rails application:

```ruby
class EmailVerificationWorker
  include XQue::Worker

  attributes :user_id

  def perform
    Mailer.user_verification(user).deliver_now
  end

  private

  def user
    @user ||= User.find(user_id)
  end
end
```

Next, create a producer to enqueue a job:

```ruby
BackgroundQueue = XQue::Producer.new(redis_url: "redis://localhost:6379/0")
```

Now we can enqueue jobs using the producer:

```ruby
BackgroundQueue.enqueue EmailVerificationWorker.new(user_id: user.id)
```

Finally, we need to start consuming jobs from the queue:

```ruby
consumers = XQue::Consumers.new(redis_url: "redis://localhost:6379/0", threads: 5)
consumers.run
```

This will start processing jobs and block forever, such that you want to start
this within a thread and call `consumers.stop` to gracefully stop it from
blocking. However, usually you just want to call `setup_traps` before calling
`run`, such that graceful termination is automatically triggered, when the
process receives a `QUIT`, `TERM` or `INT` signal:

```ruby
consumers = XQue::Consumers.new(redis_url: "redis://localhost:6379/0", threads: 5)
consumers.setup_traps
consumers.run
```

## Retries, Expiry and Backoff

The default values used by XQue are:

* expiry: 3600 (seconds)
* retries: 2
* backoff: 30, 90, 270

but you can easily change them:

```ruby
class EmailVerificationWorker
  include XQue::Worker

  xque_options expiry: 86_400, retries: 10, backoff: [5, 25, 125, 625]

  # ...
```

## Logging

You can pass a logger instance to `XQue::Consumers`, such that exceptions are
logged:

```ruby
XQue::Consumers.new(redis_url: "redis://localhost:6379/0", threads: 5, logger: Logger.new(STDOUT)).run
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake spec` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and the created tag, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/mrkamel/xque.

## License

The gem is available as open source under the terms of the [MIT
License](https://opensource.org/licenses/MIT).
