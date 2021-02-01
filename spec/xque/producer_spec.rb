class ProducerTestWorker
  include XQue::Worker

  attributes :key
end

RSpec.describe XQue::Producer do
  describe "#enqueue" do
    before do
      allow(SecureRandom).to receive(:hex).with(16).and_return("job_id")
    end

    context "with default queue name" do
      let(:producer) { described_class.new(redis_url: ENV.fetch("REDIS_URL")) }

      it "adds the job id and job to xque:jobs" do
        producer.enqueue ProducerTestWorker.new(key: "value")

        job = JSON.generate(id: "job_id", class: "ProducerTestWorker", attributes: { key: "value" }, expiry: 3_600)

        expect(RedisClient.hgetall("xque:jobs")).to eq("job_id" => job)
      end

      it "adds the job id to xque:queue:default" do
        producer.enqueue ProducerTestWorker.new

        expect(RedisClient.lrange("xque:queue:default", 0, 10)).to eq(["job_id"])
      end

      it "returns the job id" do
        expect(producer.enqueue(ProducerTestWorker.new)).to eq("job_id")
      end
    end

    context "with custom queue name" do
      let(:producer) { described_class.new(redis_url: ENV.fetch("REDIS_URL"), queue_name: "custom") }

      it "adds the job id to xque:queue:custom" do
        producer.enqueue ProducerTestWorker.new

        expect(RedisClient.lrange("xque:queue:custom", 0, 10)).to eq(["job_id"])
      end

      it "returns the job id" do
        expect(producer.enqueue(ProducerTestWorker.new)).to eq("job_id")
      end
    end
  end
end
