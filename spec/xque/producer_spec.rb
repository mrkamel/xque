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

          jobs = RedisConnection.hgetall("xque:jobs").transform_values { |value| JSON.parse(value) }

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

      it "adds the job id to the queue" do
        jid = producer.enqueue(ProducerTestWorker.new)

        expect(RedisConnection.zrange("xque:queue:items", 0, 10)).to eq([jid])
      end

      it "returns the job id" do
        allow(SecureRandom).to receive(:hex).with(16).and_return("jid")

        expect(producer.enqueue(ProducerTestWorker.new)).to eq("jid")
      end

      it "encodes the score correctly" do
        jid1 = producer.enqueue(ProducerTestWorker.new, priority: 0)
        jid2 = producer.enqueue(ProducerTestWorker.new, priority: 2)
        jid3 = producer.enqueue(ProducerTestWorker.new, priority: -2)
        jid4 = producer.enqueue(ProducerTestWorker.new, priority: 4)
        jid5 = producer.enqueue(ProducerTestWorker.new, priority: -4)

        expect(RedisConnection.zrange("xque:queue:items", 0, 10, with_scores: true)).to eq(
          [
            [jid4, (-4 << 50) | 4],
            [jid2, (-2 << 50) | 2],
            [jid1, (0 << 50) | 1],
            [jid3, (2 << 50) | 3],
            [jid5, (4 << 50) | 5]
          ]
        )
      end
    end

    context "with custom queue name" do
      let(:producer) { described_class.new(redis_url: ENV.fetch("REDIS_URL"), queue_name: "custom") }

      it "adds the job id to xque:queue:custom" do
        jid = producer.enqueue(ProducerTestWorker.new)

        expect(RedisConnection.zrange("xque:queue:custom", 0, 10)).to eq([jid])
      end

      it "returns the job id" do
        allow(SecureRandom).to receive(:hex).with(16).and_return("jid")

        expect(producer.enqueue(ProducerTestWorker.new)).to eq("jid")
      end
    end
  end

  describe "#queue_size" do
    it "returns 0 when there no queued jobs" do
      expect(producer.queue_size).to eq(0)
    end

    it "returns the number of jobs in the queue" do
      producer.enqueue(ProducerTestWorker.new(key: "value"))
      producer.enqueue(ProducerTestWorker.new(key: "value"))
      producer.enqueue(ProducerTestWorker.new(key: "value"))

      expect(producer.queue_size).to eq(3)
    end
  end

  describe "#pending_size" do
    it "returns 0 when there are no pending jobs" do
      expect(producer.pending_size).to eq(0)
    end

    it "returns the number of pending jobs" do
      jid1 = producer.enqueue(ProducerTestWorker.new(key: "value"))
      jid2 = producer.enqueue(ProducerTestWorker.new(key: "value"))
      jid3 = producer.enqueue(ProducerTestWorker.new(key: "value"))

      RedisConnection.del("xque:queue:items")

      RedisConnection.zadd("xque:pending:items", RedisConnection.time[0] + 100, jid1)
      RedisConnection.zadd("xque:pending:items", RedisConnection.time[0] + 100, jid2)
      RedisConnection.zadd("xque:pending:items", RedisConnection.time[0] + 100, jid3)

      expect(producer.pending_size).to eq(3)
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

      RedisConnection.del("xque:queue:items")
      RedisConnection.zadd("xque:pending:items", RedisConnection.time[0] + 100, jid)

      expect(producer.pending_time(jid)).to be_between(95, 105)
    end
  end
end
