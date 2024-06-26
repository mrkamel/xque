module XQue
  # The XQue::Consumer consumes and performs jobs from a specified queue.
  #
  # @example
  #   consumer = XQue::Consumer.new(redis_url: "redis://localhost:6379/0", queue_name: "default")
  #   consumer.run

  class Consumer
    DEFAULT_BACKOFF = 60
    SLEEP_INTERVAL = 5

    # Initializes a new consumer.
    #
    # @param redis_url [String] The redis url to connect to.
    # @param queue_name [String] The name to consume jobs from.
    # @param logger [Logger] A logger instance to log e.g. errors to.
    #
    # @example
    #   XQue::Consumer.new(redis_url: "...", queue_name: "default")

    def initialize(redis_url:, queue_name:, logger: Logger.new("/dev/null"))
      @redis = Redis.new(url: redis_url)
      @queue_name = queue_name
      @logger = logger

      @wakeup_queue = Queue.new
      @stopped = false
    end

    # Starts to consume and perform jobs from the queue. Blocks until
    # gracefully stopped.
    #
    # @example
    #   consumer = XQue::Consumer.new(redis_url: "...", queue_name: "default")
    #   consumer.run

    def run
      run_once until @stopped
    end

    # Gracefully stops the consumer.
    #
    # @example
    #   consumer = XQue::Consumer.new(redis_url: "...", queue_name: "default")
    #   # ...
    #   consumer.stop

    def stop
      @stopped = true
      @wakeup_queue.enq(1)
    end

    # @api private

    def run_once
      job = dequeue

      unless job
        wait

        return
      end

      perform(job)
    rescue StandardError => e
      @logger.error(e)

      sleep(SLEEP_INTERVAL)
    end

    private

    def wait
      Thread.new do
        sleep(SLEEP_INTERVAL)

        @wakeup_queue.enq(1)
      end

      @wakeup_queue.deq
    end

    def perform(job)
      object = JSON.parse(job)
      worker = Object.const_get(object["class"]).new(object["args"])

      begin
        worker.perform

        delete(job)
      rescue StandardError => e
        backoff(job)

        @logger.error(e)
      end
    end

    def dequeue
      @dequeue_script ||= <<~SCRIPT
        local queue_name = ARGV[1]

        local zitem = redis.call('zrange', 'xque:pending:' .. queue_name, 0, 0, 'WITHSCORES')
        local job_id = zitem[1]

        if not zitem[2] or tonumber(zitem[2]) > tonumber(redis.call('time')[1]) then
          job_id = redis.call('zpopmin', 'xque:queue:' .. queue_name)[1]
        end

        if not job_id then return nil end

        local job = redis.call('hget', 'xque:jobs', job_id)

        if not job then return nil end

        local object = cjson.decode(job)

        redis.call('zadd', 'xque:pending:' .. queue_name, tonumber(redis.call('time')[1]) + object['expiry'], job_id)

        return job
      SCRIPT

      @redis.eval(@dequeue_script, argv: [@queue_name])
    end

    def backoff(job)
      object = JSON.parse(job)
      worker = Object.const_get(object["class"])

      retries = worker.xque_options[:retries]
      errors = (object["errors"] || 0) + 1

      if errors > retries
        delete(job)

        return
      end

      backoff_config = worker.xque_options[:backoff] || []
      backoff = backoff_config[errors - 1] || backoff_config.last || DEFAULT_BACKOFF

      updated_job = JSON.generate(object.merge("errors" => errors))

      @backoff_script ||= <<~SCRIPT
        local queue_name, job_id, job, backoff = ARGV[1], ARGV[2], ARGV[3], tonumber(ARGV[4])

        redis.call('hset', 'xque:jobs', job_id, job)
        redis.call('zrem', 'xque:pending:' .. queue_name, job_id)
        redis.call('zadd', 'xque:pending:' .. queue_name, tonumber(redis.call('time')[1]) + backoff, job_id)
      SCRIPT

      @redis.eval(@backoff_script, argv: [@queue_name, object["jid"], updated_job, backoff])
    end

    def delete(job)
      object = JSON.parse(job)

      @delete_script ||= <<~SCRIPT
        local queue_name, job_id = ARGV[1], ARGV[2]

        redis.call('hdel', 'xque:jobs', job_id)
        redis.call('zrem', 'xque:pending:' .. queue_name, job_id)
      SCRIPT

      @redis.eval(@delete_script, argv: [@queue_name, object["jid"]])
    end
  end
end
