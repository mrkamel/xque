RSpec.describe XQue::ConsumerPool do
  let(:redis_url) { ENV.fetch("REDIS_URL") }
  let(:logger) { Logger.new("/dev/null") }

  describe "#run" do
    it "creates the specified number of threads" do
      allow(Thread).to receive(:new).and_call_original

      allow_any_instance_of(XQue::Consumer).to receive(:run)

      described_class.new(redis_url: redis_url, threads: 5, queue_name: "items", logger: logger).run

      expect(Thread).to have_received(:new).exactly(5).times
    end

    it "creates the specified number of consumers" do
      consumer = Object.new
      allow(consumer).to receive(:run)

      allow(XQue::Consumer).to receive(:new).and_return(consumer)

      described_class.new(redis_url: redis_url, threads: 5, queue_name: "items", logger: logger).run

      expect(XQue::Consumer).to have_received(:new).with(redis_url: redis_url, queue_name: "items", logger: logger).exactly(5).times
    end

    it "installs traps if traps is true" do
      allow_any_instance_of(XQue::Consumer).to receive(:run)

      consumer_pool = described_class.new(redis_url: redis_url, threads: 5, queue_name: "items", logger: logger)

      allow(consumer_pool).to receive(:trap)

      consumer_pool.run(traps: true)

      expect(consumer_pool).to have_received(:trap).with("QUIT")
      expect(consumer_pool).to have_received(:trap).with("TERM")
      expect(consumer_pool).to have_received(:trap).with("INT")
    end
  end

  describe "#stop" do
    it "stops all consumers" do
      consumer = Object.new
      allow(consumer).to receive(:run)
      allow(consumer).to receive(:stop)

      allow(XQue::Consumer).to receive(:new).and_return(consumer)

      consumer_pool = described_class.new(redis_url: redis_url, threads: 5, queue_name: "items")
      consumer_pool.run
      consumer_pool.stop

      expect(consumer).to have_received(:stop).exactly(5).times
    end
  end
end
