module XQue
  # The XQue::Producer class allows to enqueue jobs to the specified queue
  # and to get other useful information about the state of the queue.
  #
  # @example
  #   MyQueue = XQue::Producer.new(redis_url: "redis://localhost:6379/0", queue_name: "default")
  #   MyQueue.enqueue MyWorker.new(param: "value")

  class Producer
    # Initializes a new producer instance.
    #
    # @param redis_url [String] The redis url to connect to.
    # @param queue_name [String] The queue name to be used.
    #
    # @example
    #   XQue::Producer.new(redis_url: "...", queue_name: "default")

    def initialize(redis_url:, queue_name: XQue::DEFAULT_QUEUE_NAME)
      @redis = Redis.new(url: redis_url)
      @queue_name = queue_name
    end

    # Enqueues the specified worker instance to the specified queue.
    #
    # @param worker The job that should be enqueued.
    # @param priority [Integer] The job priority (-4..+4), default: 0
    # @returns [String] The jid of the enqueued job.
    #
    # @example
    #   MyQueue = XQue::Producer.new(redis_url: "...", queue_name: "default")
    #   MyQueue.enqueue MyWorker.new(param: "value")

    def enqueue(worker, priority: 0)
      jid = SecureRandom.hex(16)

      args = worker.class.xque_attributes.each_with_object({}) do |name, hash|
        hash[name] = worker.send(:"#{name}")
      end

      job = JSON.generate(
        jid: jid,
        class: worker.class.name,
        args: args,
        expiry: Integer(worker.class.xque_options[:expiry]),
        created_at: Time.now.utc.iso8601
      )

      @enqueue_script ||= <<~SCRIPT
        local queue_name, jid, job, priority = ARGV[1], ARGV[2], ARGV[3], tonumber(ARGV[4])

        redis.call('hset', 'xque:jobs', jid, job)

        local sequence_number = redis.call('incr', 'xque:seq:' .. queue_name)
        local score = -priority * (2^50) + sequence_number

        redis.call('zadd', 'xque:queue:' .. queue_name, score, jid)
      SCRIPT

      @redis.eval(@enqueue_script, argv: [@queue_name, jid, job, priority])

      jid
    end

    # Returns the number of queued and pending jobs
    #
    # @returns [Integer] The number of jobs
    #
    # @example
    #   MyQueue = XQue::Producer.new(redis_url: "...", queue_name: "default")
    #   MyQueue.size #=> e.g. 15

    def size
      queue_size + pending_size
    end

    # Returns the number of queued jobs for the queue.
    #
    # @returns [Integer] The number of queued jobs.
    #
    # @example
    #   MyQueue = XQue::Producer.new(redis_url: "...", queue_name: "default")
    #   MyQueue.queue_size # => e.g. 13

    def queue_size
      @redis.zcard("xque:queue:#{@queue_name}")
    end

    # Returns the number of pending jobs for the queue.
    #
    # @returns [Integer] The number of pending jobs.
    #
    # @example
    #   MyQueue = XQue::Producer.new(redis_url: "...", queue_name: "default")
    #   MyQueue.pending_size # => e.g. 13

    def pending_size
      @redis.zcard("xque:pending:#{@queue_name}")
    end

    # Returns the job having the specified jid, if present in the queue.
    #
    # @param jid [String] The job id of the job to be fetched.
    # @returns [Hash] The job if present in the queue or nil.
    #
    # @example
    #   MyQueue = XQue::Producer.new(redis_url: "...", queue_name: "default")
    #   MyQueue.find("3a72f5...") # => { "jid" => "...", "class" => "MyWorker", ... }

    def find(jid)
      job = @redis.hget("xque:jobs", jid)

      return unless job

      JSON.parse(job)
    end

    # Iterates all jobs of the queue.
    #
    # @returns [Enum] An enum
    #
    # @example
    #   MyQueue = XQue::Producer.new(redis_url: "...", queue_name: "default")
    #
    #   MyQueue.scan_each do |job|
    #     job # => { "jid" => "...", "class" => "MyWorker", ... }
    #   end

    def scan_each
      return enum_for(__method__) unless block_given?

      ["xque:pending:#{@queue_name}", "xque:queue:#{@queue_name}"].each do |key|
        @redis.zscan_each(key).each_slice(100) do |slice|
          jobs = @redis.hmget("xque:jobs", slice.map(&:first))

          slice.each_with_index do |_, index|
            job = jobs[index]
            next unless job

            yield JSON.parse(job)
          end
        end
      end
    end

    # Returns the pending time, i.e. the time up until the job will be
    # reconsidered for processing (failed jobs, expired jobs, etc).
    #
    # @param jid [String] The job id to fetch the pending time for.
    # @returns [Integer] The pending time in seconds.
    #
    # @example
    #   MyQueue = XQue::Producer.new(redis_url: "...", queue_name: "default")
    #   MyQueue.pending_time("3a72f5...") # => e.g. 180

    def pending_time(jid)
      @pending_time_script ||= <<~SCRIPT
        local queue_name, jid = ARGV[1], ARGV[2]

        return { redis.call('time')[1], redis.call('zscore', 'xque:pending:' .. queue_name, jid) }
      SCRIPT

      time, score = @redis.eval(@pending_time_script, argv: [@queue_name, jid])

      return if time.nil? || score.nil?

      score.to_i - time.to_i
    end
  end
end
