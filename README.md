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
XQue::ConsumerPool.new(redis_url: "redis://localhost:6379/0", threads: 5).run
```

This will start processing jobs and block forever, such that you want to start
this within a thread and call `consumers.stop` when you want it to gracefully
stop. If you want the process to listen to `QUIT`, `TERM` and `INT` to trigger
graceful termination, simply use:

```ruby
XQue::ConsumerPool.new(redis_url: "redis://localhost:6379/0", threads: 5).run(traps: true)
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

You can pass a logger instance to `XQue::ConsumerPool`, such that exceptions are
logged:

```ruby
XQue::ConsumerPool.new(redis_url: "redis://localhost:6379/0", threads: 5, logger: Logger.new(STDOUT)).run
```

## Internals

When you enqueue a job, it is added to a redis list. Consumers pop jobs from
the list and add them to a redis sorted set of pending jobs. This happens
atomically, such that no jobs get lost in between. A sorted set is used,
because we can sort the items in the sorted set by `expiry`, such that
consumers can just read the first item from the sorted set and know if it is
expired or not. If it is not expired, there can be no other expired jobs, such
that this check is quite efficient. Actually, before consumers try to pop items
from the redis list, they first always try to read the first item from the
sorted set to check if it is expired. When the job in the sorted set is
expired, it's `expiry` value gets updated and the job gets processed again.
This read-and-update operation happens atomically as well, such there won't be
two consumers which update and re-process the same job. If no items from the
sorted set are expired, the consumer tries to pop a job from the redis list
and, as already stated, atomically adds it to the sorted set of pending jobs.
Similarly, when a job fails, the `backoff` values are used to update the job's
expiry value, up until the maximum number of retries is reached or the job
succeeds. When a job succeeds it is simply removed from the pending jobs.

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
