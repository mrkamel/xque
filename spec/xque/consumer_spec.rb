class ConsumerTestWorker
  include XQue::Worker

  xque_options backoff: [60], retries: 1

  attributes :attribute1, :attribute2

  def perform; end
end

RSpec.describe XQue::Consumer do
  let(:consumer) { XQue::Consumer.new(redis_url: redis_url, queue_name: "items", logger: logger) }
  let(:producer) { XQue::Producer.new(redis_url: redis_url, queue_name: "items") }
  let(:redis_url) { ENV.fetch("REDIS_URL") }
  let(:logger) { Logger.new("/dev/null") }

  describe "#run_once" do
    it "sleeps for some time when no job is present" do
      allow(consumer).to receive(:sleep)

      consumer.run_once

      expect(consumer).to have_received(:sleep).with(described_class::SLEEP_INTERVAL)
    end

    it "performs a job and deletes it" do
      allow_any_instance_of(ConsumerTestWorker).to receive(:perform) do |worker|
        RedisConnection.hset("result", attribute1: worker.attribute1, attribute2: worker.attribute2)
      end

      producer.enqueue ConsumerTestWorker.new(attribute1: "value1", attribute2: "value2")
      producer.enqueue ConsumerTestWorker.new(attribute1: "value3", attribute2: "value4")

      consumer.run_once

      expect(RedisConnection.hgetall("result")).to eq("attribute1" => "value1", "attribute2" => "value2")
      expect(RedisConnection.zcard("xque:pending:items")).to eq(0)
      expect(RedisConnection.hlen("xque:jobs")).to eq(1)
    end

    it "adds popped jobs to the pending list with correct expiry" do
      pending = nil

      allow_any_instance_of(ConsumerTestWorker).to receive(:perform) do
        pending = RedisConnection.zrange("xque:pending:items", 0, 10, withscores: true)
      end

      job_id = producer.enqueue(ConsumerTestWorker.new(attribute1: "value1", attribute2: "value2"))

      consumer.run_once

      expect(pending.first[0]).to eq(job_id)
      expect(pending.first[1]).to be_between(Time.now.to_i + 3_600 - 5, Time.now.to_i + 3_600 + 5)
    end

    it "pops jobs from the pending list when expired" do
      job_id = producer.enqueue(ConsumerTestWorker.new(attribute1: "value1", attribute2: "value2"))

      RedisConnection.del("xque:queue:items")
      RedisConnection.zadd("xque:pending:items", RedisConnection.time[0] - 5, job_id)

      consumer.run_once

      expect(RedisConnection.zcard("xque:pending:items")).to eq(0)
      expect(RedisConnection.hlen("xque:jobs")).to eq(0)
    end

    it "does not pop jobs from the pending list when not yet expired" do
      job_id = producer.enqueue(ConsumerTestWorker.new(attribute1: "value1", attribute2: "value2"))

      RedisConnection.del("xque:queue:items")
      RedisConnection.zadd("xque:pending:items", RedisConnection.time[0] + 5, job_id)

      allow(consumer).to receive(:sleep)

      consumer.run_once

      expect(RedisConnection.zcard("xque:pending:items")).to eq(1)
    end

    it "backs off failed jobs" do
      allow_any_instance_of(ConsumerTestWorker).to receive(:perform) { raise("error") }

      job_id = producer.enqueue(ConsumerTestWorker.new(attribute1: "value1", attribute2: "value2"))

      consumer.run_once

      expect(RedisConnection.zscore("xque:pending:items", job_id)).to be_between(RedisConnection.time[0] + 55, RedisConnection.time[0] + 65)
      expect(RedisConnection.hlen("xque:jobs")).to eq(1)
    end

    it "does not back off failed jobs when the maximum amout of retries is reached" do
      allow_any_instance_of(ConsumerTestWorker).to receive(:perform) { raise("error") }

      job_id = producer.enqueue(ConsumerTestWorker.new(attribute1: "value1", attribute2: "value2"))

      consumer.run_once

      RedisConnection.zadd("xque:pending:items", RedisConnection.time[0] - 5, job_id)

      consumer.run_once

      expect(RedisConnection.zcard("xque:pending:items")).to eq(0)
      expect(RedisConnection.hlen("xque:jobs")).to eq(0)
    end

    it "logs the exception but does not raise when the job processing fails" do
      error = StandardError.new("error")

      allow_any_instance_of(ConsumerTestWorker).to receive(:perform) { raise(error) }

      allow(logger).to receive(:error)

      producer.enqueue ConsumerTestWorker.new

      expect { consumer.run_once }.not_to raise_error
      expect(logger).to have_received(:error).with(error)
    end
  end

  describe "#run and #stop" do
    it "runs until stopped" do
      5.times { producer.enqueue ConsumerTestWorker.new(attribute1: "value1", attribute2: "value2") }

      processed = 0

      allow_any_instance_of(ConsumerTestWorker).to receive(:perform) do
        processed += 1

        consumer.stop if processed == 4
      end

      consumer.run

      expect(processed).to eq(4)
    end
  end
end
