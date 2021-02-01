module XQue
  class Consumers
    def initialize(redis_url:, threads:, queue_name: XQue::DEFAULT_QUEUE_NAME, logger: Logger.new("/dev/null"))
      @redis_url = redis_url
      @threads = threads
      @queue_name = queue_name
      @logger = logger

      @consumers = []
    end

    def run
      @consumers = Array.new(@threads) do
        Consumer.new(redis_url: @redis_url, queue_name: @queue_name, logger: @logger)
      end

      consumer_threads = @consumers.map do |consumer|
        Thread.new { consumer.run }
      end

      consumer_threads.each(&:join)
    end

    def setup_traps
      %w[QUIT TERM INT].each do |signal|
        trap(signal) { stop }
      end
    end

    def stop
      @consumers.each(&:stop)
    end
  end
end
