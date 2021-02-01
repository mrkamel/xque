RSpec.describe XQue::Consumers do
  let(:redis_url) { ENV.fetch("REDIS_URL") }
  let(:logger) { Logger.new("/dev/null") }

  describe "#run" do
    it "creates the specified number of threads" do
      allow(Thread).to receive(:new).and_call_original

      allow_any_instance_of(XQue::Consumer).to receive(:run)

      consumers = described_class.new(redis_url: redis_url, threads: 5, queue_name: "items", logger: logger)
      consumers.run

      expect(Thread).to have_received(:new).exactly(5).times
    end

    it "creates the specified number of consumers" do
      consumer = Object.new
      allow(consumer).to receive(:run)

      allow(XQue::Consumer).to receive(:new).and_return(consumer)

      consumers = described_class.new(redis_url: redis_url, threads: 5, queue_name: "items", logger: logger)
      consumers.run

      expect(XQue::Consumer).to have_received(:new).with(redis_url: redis_url, queue_name: "items", logger: logger).exactly(5).times
    end
  end

  describe "#setup_traps" do
    it "installs traps" do
      consumers = described_class.new(redis_url: redis_url, threads: 5, queue_name: "items", logger: logger)

      allow(consumers).to receive(:trap)

      consumers.setup_traps

      expect(consumers).to have_received(:trap).with("QUIT")
      expect(consumers).to have_received(:trap).with("TERM")
      expect(consumers).to have_received(:trap).with("INT")
    end
  end

  describe "#stop" do
    it "stops all consumers" do
      consumer = Object.new
      allow(consumer).to receive(:run)
      allow(consumer).to receive(:stop)

      allow(XQue::Consumer).to receive(:new).and_return(consumer)

      consumers = described_class.new(redis_url: redis_url, threads: 5, queue_name: "items")
      consumers.run
      consumers.stop

      expect(consumer).to have_received(:stop).exactly(5).times
    end
  end
end
