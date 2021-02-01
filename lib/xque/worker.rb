module XQue
  module Worker
    def self.included(base)
      base.extend(ClassMethods)

      base.xque_class_attribute :xque_attributes
      base.xque_attributes = []

      base.xque_class_attribute :xque_options_hash
      base.xque_options_hash = { expiry: 3_600, retries: 2, backoff: [30, 90, 270] }
    end

    def initialize(attributes = {})
      attributes.each do |name, value|
        raise(ArgumentError, "Unknown attribute #{name}") unless self.class.xque_attributes.include?(name.to_s)

        send(:"#{name}=", value)
      end
    end

    module ClassMethods
      def xque_class_attribute(name)
        define_singleton_method(:"#{name}=") do |val|
          define_singleton_method(:"#{name}") { val }
        end

        send(:"#{name}=", nil)
      end

      def attributes(*attrs)
        self.xque_attributes = xque_attributes + attrs.map(&:to_s)

        attr_accessor(*attrs)
      end

      def xque_options(options = {})
        self.xque_options_hash = xque_options_hash.merge(options)
      end
    end
  end
end
