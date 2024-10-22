module GlueGun
  module Model
    extend ActiveSupport::Concern

    included do
      before_save :serialize_service_object
      after_find :deserialize_service_object

      class_attribute :service_class_resolver
      class_attribute :service_class
      class_attribute :service_attribute_name

      # Set default service attribute name based on the class name
      self.service_attribute_name = "#{name.demodulize.underscore}_service".to_sym
      # self.delegated_methods = []
    end

    class_methods do
      def service(class_or_proc = nil, &block)
        if class_or_proc.is_a?(Class)
          self.service_class = class_or_proc
        elsif block_given?
          self.service_class_resolver = block
        else
          raise ArgumentError, "You must provide a service class, factory, or a block to resolve the service class."
        end
      end

      # def delegate_service_methods(*methods)
      #   methods.each do |method_name|
      #     delegated_methods << method_name.to_sym

      #     define_method(method_name) do |*args, &block|
      #       service_object = instance_variable_get("@#{service_attribute_name}")
      #       service_object.send(method_name, *args, &block)
      #     end
      #   end
      # end
    end

    def initialize(attributes = {})
      attributes = attributes.deep_symbolize_keys
      db_attributes = extract_db_attributes(attributes)
      super(db_attributes)
      self.class.send(:attr_reader, service_attribute_name)
      build_service_object(attributes)
    end

    private

    def extract_db_attributes(attributes)
      # Extract attributes that correspond to database columns or associations
      column_names = self.class.column_names.map(&:to_sym)
      association_names = self.class.reflect_on_all_associations.map(&:name)

      attributes.slice(*(column_names + association_names))
    end

    def build_service_object(attributes)
      service_class = resolve_service_class(attributes)
      service_attributes = extract_service_attributes(attributes, service_class)
      service_instance = service_class.new(service_attributes)
      instance_variable_set("@#{service_attribute_name}", service_instance)
      # define_service_delegators(service_class)
    end

    def resolve_service_class(attributes)
      if self.class.service_class
        self.class.service_class
      elsif self.class.service_class_resolver
        self.class.service_class_resolver.call(attributes)
      else
        raise "Service class not defined for #{self.class.name}"
      end
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

    def serialize_service_object
      service_object = instance_variable_get("@#{service_attribute_name}")
      service_klass = service_object.class
      attrs = service_klass.respond_to?(:serialize) ? service_klass.serialize(service_object) : service_object.attributes
      deps = allowed_names(service_object.dependency_definitions.keys).inject({}) do |hash, dep|
        hash.tap do
          this_dep = service_object.send(dep)
          next unless this_dep.present?

          opts = service_object.dependency_definitions[dep].option_configs
          selected_option = opts.detect do |_k, v|
            this_dep.class == v.class_name
          end&.first
          unless selected_option.present?
            raise "Don't know how to serialize dependency of type #{dep}, available options are #{opts.keys}. You didn't specify an option."
          end

          hash[dep] = {
            selected_option => service_object.send(dep).attributes
          }
        end
      end
      json = attrs.merge(deps.deep_compact).deep_symbolize_keys
      write_attribute(:configuration, json.to_json)
    end

    def deserialize_service_object
      serialized_data = JSON.parse(read_attribute(:configuration) || "{}")
      serialized_data.deep_symbolize_keys!
      service_class = resolve_service_class(serialized_data)
      serialized_data = service_class.deserialize(serialized_data) if service_class.respond_to?(:deserialize)
      service_instance = service_class.new(serialized_data)
      instance_variable_set("@#{service_attribute_name}", service_instance)
      # define_service_delegators(service_class)
    end

    def allowed_names(names)
      assoc_names = self.class.reflect_on_all_associations.map(&:name)
      [names.map(&:to_sym) - assoc_names.map(&:to_sym)].flatten
    end

    def serialize
      dataset_service.attributes
      write_attribute(:configuration, json.to_json)
    end

    def deserialize
      options = JSON.parse(read_attribute(:configuration))
      options.deep_symbolize_keys!

      build_dataset_service(options)
    end

    def method_missing(method_name, *args, &block)
      service_object = instance_variable_get("@#{service_attribute_name}")

      if service_object && service_object.respond_to?(method_name)
        service_object.send(method_name, *args, &block)
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
