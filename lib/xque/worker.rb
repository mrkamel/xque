module XQue
  # The XQue::Worker mixin should be used in your worker classes.
  #
  # @example
  #   class MyWorker
  #     include XQue::Worker
  #
  #     xque_options expiry: 1_800, retries: 5, backoff: [50, 100, 200]
  #
  #     attributes :param1, :param2
  #   end
  #
  #   MyQueue.enqueue MyWorker.new(param1: "value1", param2: "value2")

  module Worker
    def self.included(base)
      base.extend(ClassMethods)

      base.xque_class_attribute :xque_attributes
      base.xque_attributes = []

      base.xque_class_attribute :xque_options_hash
      base.xque_options_hash = { expiry: 3_600, retries: 2, backoff: [30, 90, 270] }
    end

    # Initializes the worker instance and assigns all the passed attributes.
    #
    # @param attributes [Hash] The attributes to be assigned.
    #
    # @example
    #   MyWorker.new(param1: "value1", param2: "value2")

    def initialize(attributes = {})
      attributes.each do |name, value|
        raise(ArgumentError, "Unknown attribute #{name}") unless self.class.xque_attributes.include?(name.to_s)

        send(:"#{name}=", value)
      end
    end

    module ClassMethods
      # @api private

      def xque_class_attribute(name)
        define_singleton_method(:"#{name}=") do |val|
          define_singleton_method(:"#{name}") { val }
        end

        send(:"#{name}=", nil)
      end

      # Adds the specified attribute, such that the attribute will be
      # serialized when the job gets enqueued and creates accessors for the
      # attribute.
      #
      # @param attrs The attributes to add.

      def attributes(*attrs)
        self.xque_attributes = xque_attributes + attrs.map(&:to_s)

        attr_accessor(*attrs)
      end

      # Merges the specified worker options into the default options.
      #
      # @param options [Hash] The options to be merged.
      #
      # @example
      #   class MyWorker
      #     include XQue::Worker
      #
      #     xque_options expiry: 1_800, retries: 5, backoff: [50, 100, 200]
      #   end

      def xque_options(options = {})
        self.xque_options_hash = xque_options_hash.merge(options)
      end
    end
  end
end
