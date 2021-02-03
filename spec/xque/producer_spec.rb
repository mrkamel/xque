class ProducerTestWorker
  include XQue::Worker

  attributes :key
end

RSpec.describe XQue::Producer do
  let(:producer) { described_class.new(redis_url: ENV.fetch("REDIS_URL"), queue_name: "items") }

  describe "#enqueue" do
    context "with default queue name" do
      it "adds the job id and job to xque:jobs" do
        Timecop.freeze Time.parse("2021-01-01 12:00:00 UTC") do
          jid = producer.enqueue(ProducerTestWorker.new(key: "value"))

          jobs = RedisClient.hgetall("xque:jobs").transform_values { |value| JSON.parse(value) }

          expect(jobs).to match(
            jid => {
              "jid" => jid,
              "class" => "ProducerTestWorker",
              "args" => { "key" => "value" },
              "expiry" => 3_600,
              "created_at" => "2021-01-01T12:00:00Z"
            }
          )
        end
      end

      it "adds the job id to xque:queue:default" do
        jid = producer.enqueue(ProducerTestWorker.new)

        expect(RedisClient.lrange("xque:queue:items", 0, 10)).to eq([jid])
      end

      it "returns the job id" do
        allow(SecureRandom).to receive(:hex).with(16).and_return("jid")

        expect(producer.enqueue(ProducerTestWorker.new)).to eq("jid")
      end
    end

    context "with custom queue name" do
      let(:producer) { described_class.new(redis_url: ENV.fetch("REDIS_URL"), queue_name: "custom") }

      it "adds the job id to xque:queue:custom" do
        jid = producer.enqueue(ProducerTestWorker.new)

        expect(RedisClient.lrange("xque:queue:custom", 0, 10)).to eq([jid])
      end

      it "returns the job id" do
        allow(SecureRandom).to receive(:hex).with(16).and_return("jid")

        expect(producer.enqueue(ProducerTestWorker.new)).to eq("jid")
      end
    end
  end

  describe "#find" do
    it "returns nil when the job can not be found" do
      expect(producer.find("unknown")).to be_nil
    end

    it "returns the job having the specified id" do
      Timecop.freeze Time.parse("2021-01-01 12:00:00 UTC") do
        jid = producer.enqueue(ProducerTestWorker.new(key: "value"))

        expect(producer.find(jid)).to match(
          "jid" => jid,
          "args" => { "key" => "value" },
          "class" => "ProducerTestWorker",
          "expiry" => 3600,
          "created_at" => "2021-01-01T12:00:00Z"
        )
      end
    end
  end

  describe "#pending_time" do
    it "returns nil when the job can not be found" do
      expect(producer.pending_time("unknown")).to be_nil
    end

    it "returns nil when the job is not pending" do
      jid = producer.enqueue(ProducerTestWorker.new(key: "value"))

      expect(producer.pending_time(jid)).to be_nil
    end

    it "returns the pending time" do
      jid = producer.enqueue(ProducerTestWorker.new(key: "value"))

      RedisClient.del("xque:queue:items")
      RedisClient.zadd("xque:pending:items", RedisClient.time[0] + 100, jid)

      expect(producer.pending_time(jid)).to be_between(95, 105)
    end
  end
end
