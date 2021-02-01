RSpec.describe XQue::Worker do
  describe ".attributes" do
    it "adds the attribute names to the xque attributes" do
      klass = Class.new do
        include XQue::Worker

        attributes :attribute1, :attribute2
        attributes :attribute3
      end

      expect(klass.xque_attributes).to eq(%w[attribute1 attribute2 attribute3])
    end

    it "keeps the attributes from the parent class" do
      parent = Class.new do
        include XQue::Worker

        attributes :attribute1, :attribute2
      end

      child = Class.new(parent) do
        attributes :attribute3
      end

      expect(child.xque_attributes).to eq(%w[attribute1 attribute2 attribute3])
    end

    it "adds accessors for the attributes" do
      klass = Class.new do
        include XQue::Worker

        attributes :attribute1, :attribute2
      end

      worker = klass.new
      worker.attribute1 = "value1"
      worker.attribute2 = "value2"

      expect(worker.attribute1).to eq("value1")
      expect(worker.attribute2).to eq("value2")
    end

    it "sets a empty attribute list by default" do
      klass = Class.new do
        include XQue::Worker
      end

      expect(klass.xque_attributes).to eq([])
    end
  end

  describe ".xque_options" do
    it "adds the options to xque_options_hash" do
      klass = Class.new do
        include XQue::Worker

        xque_options key1: "value1", key2: "value2"
      end

      expect(klass.xque_options_hash).to match(hash_including(key1: "value1", key2: "value2"))
    end

    it "keeps the options from the parent class" do
      parent = Class.new do
        include XQue::Worker

        xque_options key1: "value1", key2: "value2"
      end

      child = Class.new(parent) do
        xque_options key3: "value3"
      end

      expect(child.xque_options_hash).to match(hash_including(key1: "value1", key2: "value2", key3: "value3"))
    end

    it "sets default options" do
      klass = Class.new do
        include XQue::Worker
      end

      expect(klass.xque_options_hash).to eq(retries: 2, expiry: 3_600, backoff: [30, 90, 270])
    end
  end

  describe "initialize" do
    let(:klass) do
      Class.new do
        include XQue::Worker

        attributes :attribute1, :attribute2
      end
    end

    it "sets the attributes" do
      worker = klass.new(attribute1: "value1", attribute2: "value2")

      expect(worker.attribute1).to eq("value1")
      expect(worker.attribute2).to eq("value2")
    end

    it "raises an ArgumentError when the attribute is unknown" do
      expect { klass.new(unknown: "value") }.to raise_error(ArgumentError)
    end
  end
end
