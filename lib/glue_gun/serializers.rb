module GlueGun
  class Serializers
    attr_accessor :instance

    def initialize(instance)
      @instance = instance
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

    def serialize_dependency(service_object, dependency, dep_instance = nil)
      dep_instance = service_object.send(dependency) if dep_instance.nil?
      return nil unless dep_instance.present?

      if dep_instance.is_a?(Array)
        return dep_instance.map do |dep|
          serialize_dependency(service_object, dependency, dep)
        end
      end

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

    def service_class
      service_object.class
    end

    def allowed_names(names)
      assoc_names = instance.class.reflect_on_all_associations.map(&:name)
      [names.map(&:to_sym) - assoc_names.map(&:to_sym)].flatten
    end

    def serialize_service_object(service_object)
      attrs = serialize_object(service_object)
      deps = allowed_names(service_object.dependency_definitions.keys).inject({}) do |hash, dep|
        hash.tap do
          serialized = serialize_dependency(service_object, dep)
          next if serialized.nil?

          hash[dep] = serialized
        end
      end
      json = serializable!(serialize_attrs(attrs.merge(deps).deep_symbolize_keys))
      instance.write_attribute(:configuration, json.to_json)
    end

    def serializable!(json)
      regular_args = json.slice(*allowed_names(json.keys))
      assoc_names = instance.class.reflect_on_all_associations.map(&:name)
      found_associations = assoc_names & json.keys
      found_associations.each do |association|
        regular_args[association] = true
      end
      regular_args
    end

    def deserialize_associations(json)
      assoc_names = instance.class.reflect_on_all_associations.map(&:name)
      found_associations = assoc_names & json.keys
      found_associations.each do |association|
        json[association] = instance.send(association)
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
      serialized_data = JSON.parse(instance.read_attribute(:configuration) || "{}")
      serialized_data.deep_symbolize_keys!
      serialized_data = deserialize_attrs(serialized_data)
      service_class = instance.send(:resolve_service_class, serialized_data)
      serialized_data = deserialize_associations(serialized_data)
      serialized_data = service_class.deserialize(serialized_data) if service_class.respond_to?(:deserialize)
      deserialize_dependencies(serialized_data, service_class)
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
  end
end
