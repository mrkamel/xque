module XQue
  class Producer
    def initialize(redis_url:, queue_name: XQue::DEFAULT_QUEUE_NAME)
      @redis = Redis.new(url: redis_url)
      @queue_name = queue_name
    end

    def enqueue(worker)
      job_id = SecureRandom.hex(16)

      args = worker.class.xque_attributes.each_with_object({}) do |name, hash|
        hash[name] = worker.send(:"#{name}")
      end

      job = JSON.generate(
        jid: job_id,
        class: worker.class.name,
        args: args,
        expiry: Integer(worker.class.xque_options[:expiry]),
        created_at: Time.now.utc.iso8601
      )

      @enqueue_script ||= <<~SCRIPT
        local queue_name, job_id, job = ARGV[1], ARGV[2], ARGV[3]

        redis.call('hset', 'xque:jobs', job_id, job)
        redis.call('lpush', 'xque:queue:' .. queue_name, job_id)
      SCRIPT

      @redis.eval(@enqueue_script, argv: [@queue_name, job_id, job])

      job_id
    end

    def queue_size
      @redis.llen("xque:queue:#{@queue_name}")
    end

    def pending_size
      @redis.zcard("xque:pending:#{@queue_name}")
    end

    def find(job_id)
      job = @redis.hget("xque:jobs", job_id)

      return unless job

      JSON.parse(job)
    end

    def pending_time(job_id)
      @pending_time_script ||= <<~SCRIPT
        local queue_name, job_id = ARGV[1], ARGV[2]

        return { redis.call('time')[1], redis.call('zscore', 'xque:pending:' .. queue_name, job_id) }
      SCRIPT

      time, score = @redis.eval(@pending_time_script, argv: [@queue_name, job_id])

      return if time.nil? || score.nil?

      score.to_i - time.to_i
    end
  end
end
