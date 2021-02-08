module XQue
  # The XQue::ConsumerPool creates a thread pool of consumers for a queue.
  #
  # @example
  #   consumer_pool = XQue::ConsumerPool.new(redis_url: "redis://localhost:6379/0", threads: 5)
  #   consumer_pool.run

  class ConsumerPool
    # Initializes a new consumer thread pool.
    #
    # @param redis_url [String] The redis url to connect to.
    # @param threads [Integer] The number of threads to start.
    # @param queue_name [String] The queue to consume jobs from.
    # @param logger [Logger] A logger instance to log e.g. errors to.
    #
    # @example
    #   XQue::ConsumerPool.new(redis_url: "...", threads: 5, logger: Logger.new(STDOUT))

    def initialize(redis_url:, threads:, queue_name: XQue::DEFAULT_QUEUE_NAME, logger: Logger.new("/dev/null"))
      @redis_url = redis_url
      @threads = threads
      @queue_name = queue_name
      @logger = logger

      @consumers = []
    end

    # Starts the number of threads, optionally setting up traps for graceful
    # termination, and begins to consume jobs. Blocks until all jobs are
    # terminated.
    #
    # @param traps [Boolean] Whether or not to setup traps for graceful
    #   termination.
    #
    # @example
    #   consumer_pool = XQue::ConsumerPool.new(redis_url: "...", threads: 5)
    #   consumer_pool.run

    def run(traps: false)
      @consumers = Array.new(@threads) do
        Consumer.new(redis_url: @redis_url, queue_name: @queue_name, logger: @logger)
      end

      setup_traps if traps

      consumer_threads = @consumers.map do |consumer|
        Thread.new { consumer.run }
      end

      consumer_threads.each(&:join)
    end

    # Manually triggers graceful termination of the consumer pool, by
    # signalling each consumer thread to stop.
    #
    # @example
    #   consumer_pool = XQue::ConsumerPool.new(redis_url: "...", threads: 5)
    #   # ...
    #   consumer_pool.stop

    def stop
      @consumers.each(&:stop)
    end

    private

    def setup_traps
      %w[QUIT TERM INT].each do |signal|
        trap(signal) { stop }
      end
    end
  end
end
