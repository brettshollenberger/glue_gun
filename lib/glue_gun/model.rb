require_relative "shared"
module GlueGun
  module Model
    extend ActiveSupport::Concern

    class ServiceRegistry
      attr_accessor :services

      def register(k, v)
        @services ||= {}
        @services[k.to_sym] = v
      end

      def options
        services.keys
      end

      def []=(k, v)
        register(k, v)
      end

      def [](k)
        return nil if k.nil?

        @services ||= {}
        @services.dig(k.to_sym)
      end

      def default_key
        return unless services.keys.count == 1

        services.keys.first
      end

      def default
        default_key.present? ? services[default_key] : nil
      end
    end

    included do
      include GlueGun::Shared

      before_save :serialize_service_object
      after_find :deserialize_service_object

      class_attribute :service_class_resolver
      class_attribute :service_class
      class_attribute :service_attribute_name

      # Set default service attribute name based on the class name
      self.service_attribute_name = "#{name.demodulize.underscore}_service".to_sym

      class_attribute :service_registry
      self.service_registry = ServiceRegistry.new

      # Set default option key based on the class name
      class_attribute :option_key
      self.option_key = "#{name.demodulize.underscore}_type".to_sym

      def assign_attributes(attributes)
        return if attributes.blank?

        attributes = attributes.deep_symbolize_keys
        db_attributes = self.class.extract_db_attributes(attributes)

        # Assign database attributes
        super(db_attributes)

        assign_service_attributes(attributes)
      end
      alias_method :attributes=, :assign_attributes
    end

    class_methods do
      def service(key, service_class)
        service_registry[key] = service_class
      end

      def find_or_create_by!(attributes)
        attributes = attributes.deep_symbolize_keys
        db_attributes = extract_db_attributes(attributes)
        attributes.except(*db_attributes.keys)

        record = where(db_attributes).first_or_initialize(attributes)

        record.save! if record.new_record?
        yield record if block_given?

        record
      end

      def find_or_create_by(attributes)
        attributes = attributes.deep_symbolize_keys
        db_attributes = extract_db_attributes(attributes)
        attributes.except(*db_attributes.keys)

        record = where(db_attributes).first_or_initialize(attributes)

        record.save if record.new_record?
        yield record if block_given?

        record
      end

      def extract_db_attributes(attributes)
        # Extract attributes that correspond to database columns or associations
        column_names = self.column_names.map(&:to_sym)
        association_names = reflect_on_all_associations.map(&:name)

        attributes.slice(*(column_names + association_names))
      end
    end

    def initialize(attributes = {})
      attributes = {} if attributes.nil?
      attributes[:root_dir] ||= detect_root_dir
      attributes = attributes.deep_symbolize_keys
      attributes[option_key] ||= resolve_service_type(attributes, true)
      db_attributes = self.class.extract_db_attributes(attributes)
      super(db_attributes)
      build_service_object(attributes)
    end

    def assign_service_attributes(attributes)
      return if attributes.blank?

      service_object = instance_variable_get("@#{service_attribute_name}")
      return unless service_object.present?

      extract_service_attributes(attributes, service_object.class).each do |attr_name, value|
        unless service_object.respond_to?("#{attr_name}=")
          raise NoMethodError, "Undefined attribute #{attr_name} for #{service_object.class.name}"
        end

        service_object.send("#{attr_name}=", value)
        attribute_will_change!(attr_name.to_s)
      end
    end

    private

    def awesome_print(message)
      ap message
    end

    def build_service_object(attributes)
      self.class.send(:attr_reader, service_attribute_name)
      service_class = resolve_service_class(attributes)
      raise "Unable to find service class for #{self.class} given #{attributes}" unless service_class.present?

      service_attributes = extract_service_attributes(attributes, service_class)
      begin
        service_instance = service_class.new(service_attributes)
      rescue StandardError => e
        awesome_print %(Error building service object #{service_class}:)
        awesome_print e.message
        awesome_print e.backtrace
        raise e
      end
      instance_variable_set("@#{service_attribute_name}", service_instance)
    end

    def resolve_service_type(attributes, initializing = false)
      attrs = if initializing || !persisted? || attributes.key?(self.class.option_key)
                attributes
              elsif respond_to?(self.class.option_key)
                { self.class.option_key => send(self.class.option_key) }
              else
                { self.class.option_key => self.class.service_registry.default_key }
              end
      attrs[self.class.option_key] || self.class.service_registry.default_key
    end

    def resolve_service_class(attributes)
      type = resolve_service_type(attributes)
      service_class = self.class.service_registry[type] || self.class.service_registry.default

      unless service_class
        available_types = self.class.service_registry.options
        raise ArgumentError,
              "#{self.class} requires argument #{self.class.option_key}. Invalid option key received: #{type}. Allowed options are: #{available_types}"
      end

      service_class
    end

    def extract_service_attributes(attributes, service_class)
      allowed_attrs = service_attributes(service_class)
      attrs_and_associations(attributes).slice(*allowed_attrs)
    end

    def service_attributes(service_class)
      service_class.dependency_definitions.keys.concat(
        service_class.attribute_definitions.keys
      )
    end

    def attrs_and_associations(attributes)
      foreign_keys = foreign_key_map
      attributes.inject({}) do |h, (k, v)|
        h.tap do
          if foreign_keys.include?(k)
            assoc_name = foreign_keys[k]
            h[assoc_name] = send(assoc_name)
          else
            h[k] = v
          end
        end
      end
    end

    def foreign_key_map
      self.class.reflect_on_all_associations.inject({}) do |h, assoc|
        h.tap do
          h[assoc.foreign_key] = assoc.name
        end
      end.symbolize_keys
    end

    def serialize_object(object)
      if object.respond_to?(:serialize)
        object.serialize
      elsif object.respond_to?(:attributes)
        object.attributes.deep_compact
      else
        Hash[object.instance_variables.map do |var|
          [var.to_s.delete("@"), object.instance_variable_get(var)]
        end].deep_compact
      end
    end

    def serialize_dependency(dependency, dep_instance = nil)
      dep_instance = service_object.send(dependency) if dep_instance.nil?
      return nil unless dep_instance.present?

      return dep_instance.map { |dep| serialize_dependency(dependency, dep) } if dep_instance.is_a?(Array)

      opts = service_object.dependency_definitions[dependency].option_configs
      selected_option = opts.detect do |_k, v|
        dep_instance.class == v.class_name
      end&.first
      unless selected_option.present?
        raise "Don't know how to serialize dependency of type #{dependency}, available options are #{opts.keys}. You didn't specify an option."
      end

      serialized = serialize_object(dep_instance)
      {
        selected_option => serialized
      }
    end

    def service_object
      instance_variable_get("@#{service_attribute_name}")
    end

    def service_class
      service_object.class
    end

    def serialize_service_object
      attrs = serialize_object(service_object)
      deps = allowed_names(service_object.dependency_definitions.keys).inject({}) do |hash, dep|
        hash.tap do
          serialized = serialize_dependency(dep)
          next if serialized.nil?

          hash[dep] = serialized
        end
      end
      json = serializable!(serialize_attrs(attrs.merge(deps).deep_symbolize_keys))
      write_attribute(:configuration, json.to_json)
    end

    def serializable!(json)
      regular_args = json.slice(*allowed_names(json.keys))
      assoc_names = self.class.reflect_on_all_associations.map(&:name)
      found_associations = assoc_names & json.keys
      found_associations.each do |association|
        regular_args[association] = true
      end
      regular_args
    end

    def deserialize_associations(json)
      assoc_names = self.class.reflect_on_all_associations.map(&:name)
      found_associations = assoc_names & json.keys
      found_associations.each do |association|
        json[association] = send(association)
      end
      json
    end

    def deserialize_dependency(serialized, definition)
      return serialized.map { |dep| deserialize_dependency(dep, definition) } if serialized.is_a?(Array)

      dep_name = serialized.keys.first
      selected_option = definition.option_configs[dep_name]
      dependency_class = selected_option.class_name
      arguments = serialized[dep_name]

      dependency_class.respond_to?(:deserialize) ? dependency_class.deserialize(arguments) : arguments
      {
        dep_name => arguments
      }
    end

    def deserialize_dependencies(serialized_data, service_class)
      serialized_deps = (serialized_data.keys & allowed_names(service_class.dependency_definitions.keys))
      serialized_deps.each do |name|
        serialized = serialized_data[name]
        definition = service_class.dependency_definitions[name]
        serialized_data[name] = deserialize_dependency(serialized, definition)
      end
      serialized_data
    end

    def deserialize_service_object
      serialized_data = JSON.parse(read_attribute(:configuration) || "{}")
      serialized_data.deep_symbolize_keys!
      serialized_data = deserialize_attrs(serialized_data)
      service_class = resolve_service_class(serialized_data)
      serialized_data = deserialize_associations(serialized_data)
      serialized_data = service_class.deserialize(serialized_data) if service_class.respond_to?(:deserialize)
      serialized_data = deserialize_dependencies(serialized_data, service_class)
      service_instance = build_service_object(serialized_data)
      instance_variable_set("@#{service_attribute_name}", service_instance)
    end

    def serialize_attrs(attrs)
      attrs.deep_transform_values do |value|
        case value
        when ActiveSupport::TimeWithZone
          { "__type__" => "ActiveSupport::TimeWithZone", "value" => value.iso8601 }
        else
          value
        end
      end
    end

    def deserialize_attrs(attrs)
      return nil if attrs.nil?

      attrs.transform_values do |value|
        recursive_deserialize(value)
      end
    end

    def recursive_deserialize(value)
      case value
      when Hash
        if value[:__type__]
          deserialize_special_type(value)
        else
          value.transform_values { |v| recursive_deserialize(v) }
        end
      when Array
        value.map { |v| recursive_deserialize(v) }
      else
        value
      end
    end

    def deserialize_special_type(value)
      case value[:__type__]
      when "ActiveSupport::TimeWithZone"
        Time.zone.parse(value[:value])
      else
        value[:value]
      end
    end

    def allowed_names(names)
      assoc_names = self.class.reflect_on_all_associations.map(&:name)
      [names.map(&:to_sym) - assoc_names.map(&:to_sym)].flatten
    end

    def method_missing(method_name, *args, **kwargs, &block)
      service_object = instance_variable_get("@#{service_attribute_name}")

      if service_object && service_object.respond_to?(method_name)
        service_object.send(method_name, *args, **kwargs, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      service_object = instance_variable_get("@#{service_attribute_name}")
      service_object && service_object.respond_to?(method_name) || super
    end
  end
end
