module XQue
  class Producer
    def initialize(redis_url:, queue_name: XQue::DEFAULT_QUEUE_NAME)
      @redis = Redis.new(url: redis_url)
      @queue_name = queue_name
    end

    def enqueue(worker)
      job_id = SecureRandom.hex(16)
      attributes = worker.class.xque_attributes.each_with_object({}) { |name, hash| hash[name] = worker.send(:"#{name}") }
      job = JSON.generate(id: job_id, class: worker.class.name, attributes: attributes, expiry: Integer(worker.class.xque_options[:expiry]))

      @enqueue_script ||= <<~SCRIPT
        local queue_name, job_id, job = ARGV[1], ARGV[2], ARGV[3]

        redis.call('hset', 'xque:jobs', job_id, job)
        redis.call('lpush', 'xque:queue:' .. queue_name, job_id)
      SCRIPT

      @redis.eval(@enqueue_script, argv: [@queue_name, job_id, job])

      job_id
    end
  end
end
