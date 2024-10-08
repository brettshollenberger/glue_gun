module GlueGun
  module DSL
    extend ActiveSupport::Concern

    included do
      unless ancestors.include?(ActiveRecord::Base)
        include ActiveModel::Model
        include ActiveModel::Attributes
        include ActiveModel::Validations
        include ActiveModel::AttributeAssignment
        include ActiveModel::Dirty
        include ActiveRecord::Callbacks
      end

      class_attribute :attribute_definitions, instance_writer: false, default: {}
      class_attribute :dependency_definitions, instance_writer: false, default: {}
      class_attribute :hardcoded_dependencies, instance_writer: false, default: {}

      # Module to hold custom attribute methods
      attribute_methods_module = Module.new
      const_set(:AttributeMethods, attribute_methods_module)
      prepend attribute_methods_module

      prepend Initialization

      # Prepend ClassMethods into the singleton class of the including class
      class << self
        prepend ClassMethods
      end

      # Overriding ActiveModel.assign_attributes to ensure change propagation to dependenices
      def assign_attributes(new_attributes)
        super(new_attributes)
        propagate_changes if initialized?
      end

      if ancestors.include?(ActiveRecord::Base)
        columns.each do |column|
          # Skip if already defined via GlueGun::DSL's attribute method
          next if attribute_definitions.key?(column.name.to_sym)

          # Define a ConfigAttr for each ActiveRecord column
          attribute(column.name.to_sym, column.type)
        end
      end
    end

    module Initialization
      def initialize(attrs = {})
        attrs ||= {}
        attrs = attrs.symbolize_keys
        # Separate dependency configurations from normal attributes
        dependency_attributes = {}
        normal_attributes = {}

        attrs.each do |key, value|
          if self.class.dependency_definitions.key?(key)
            dependency_attributes[key] = value
          else
            normal_attributes[key] = value
          end
        end

        normal_attributes.reverse_merge!(root_dir: detect_root_dir) if attribute_definitions.keys.include?(:root_dir)

        # Call super to allow ActiveModel to assign attributes
        super(normal_attributes)

        # Initialize dependencies after attributes have been set
        initialize_dependencies(dependency_attributes)

        @initialized = true
      end
    end

    module ClassMethods
      DEFAULT_TYPE = if ActiveModel.version >= Gem::Version.new("7")
                       nil
                     elsif ActiveModel.version >= Gem::Version.new("5")
                       ActiveModel::Type::Value.new
                     end
      # Override the attribute method to define custom setters
      def attribute(name, type = DEFAULT_TYPE, **options)
        super(name, type, **options)
        attribute_definitions[name.to_sym] = { type: type, options: options }

        # Define dirty tracking for the attribute
        define_attribute_methods name unless ancestors.include?(ActiveRecord::Base)

        attribute_methods_module = const_get(:AttributeMethods)

        attribute_methods_module.class_eval do
          define_method "#{name}=" do |value|
            value = super(value)
            propagate_attribute_change(name, value) if initialized?
          end
        end
      end

      def dependency(component_type, &block)
        dependency_builder = DependencyBuilder.new(component_type)
        dependency_builder.instance_eval(&block)
        dependency_definitions[component_type] = dependency_builder

        # Define singleton method to allow hardcoding dependencies in subclasses
        define_singleton_method component_type do |option = nil, options = {}|
          if option.is_a?(Hash) && options.empty?
            options = option
            option = nil
          end
          option ||= dependency_builder.default_option_name
          hardcoded_dependencies[component_type] = { option_name: option, value: options }
        end

        define_method component_type do
          instance_variable_get("@#{component_type}") ||
            instance_variable_set("@#{component_type}", initialize_dependency(component_type))
        end

        attribute_methods_module = const_get(:AttributeMethods)
        attribute_methods_module.class_eval do
          define_method "#{component_type}=" do |init_args|
            instance_variable_set("@#{component_type}", initialize_dependency(component_type, init_args))
          end
        end
      end

      def inherited(subclass)
        super
        subclass.attribute_definitions = attribute_definitions.deep_dup
        subclass.dependency_definitions = dependency_definitions.deep_dup
        subclass.hardcoded_dependencies = hardcoded_dependencies.deep_dup

        # Prepend the AttributeMethods module to the subclass
        attribute_methods_module = const_get(:AttributeMethods)
        subclass.prepend(attribute_methods_module)

        # Prepend ClassMethods into the singleton class of the subclass
        class << subclass
          prepend ClassMethods
        end
      end

      def detect_root_dir
        base_path = Module.const_source_location(name)&.first || ""
        File.dirname(base_path)
      end
    end

    def initialized?
      @initialized == true
    end

    def detect_root_dir
      base_path = Module.const_source_location(self.class.name)&.first || ""
      File.dirname(base_path)
    end

    def initialize_dependencies(attributes)
      self.class.dependency_definitions.each do |component_type, _|
        value = attributes[component_type] || self.class.hardcoded_dependencies[component_type]
        instance_variable_set("@#{component_type}", initialize_dependency(component_type, value))
      end
    end

    def initialize_dependency(component_type, init_args = {})
      return init_args if dependency_injected?(component_type, init_args)

      dependency_builder = self.class.dependency_definitions[component_type]

      if init_args && init_args.is_a?(Hash) && init_args.key?(:option_name)
        option_name = init_args[:option_name]
        init_args = init_args[:value]
      else
        option_name, init_args = determine_option_name(component_type, init_args)
      end

      option_config = dependency_builder.option_configs[option_name]

      raise ArgumentError, "Unknown #{component_type} option '#{option_name}'" unless option_config

      dep_attributes = init_args.is_a?(Hash) ? init_args : {}

      # Build dependency attributes, including sourcing from parent
      dep_attributes = build_dependency_attributes(option_config, dep_attributes)

      if dep_attributes.key?(:id)
        raise ArgumentError,
              "cannot bind attribute 'id' between #{self.class.name} and #{option_config.class_name}. ID is reserved for primary keys in Ruby on Rails"
      end

      dependency_instance = instantiate_dependency(option_config, dep_attributes)

      # Keep track of dependencies for attribute binding
      dependencies[component_type] = {
        instance: dependency_instance,
        option: option_config
      }

      dependency_instance
    end

    def build_dependency_attributes(option_config, dep_attributes)
      option_config.attributes.each do |attr_name, attr_config|
        # If the attribute is already provided, use it
        if dep_attributes.key?(attr_name)
          value = dep_attributes[attr_name]
        else
          value = if attr_config.source && respond_to?(attr_config.source)
                    send(attr_config.source)
                  elsif respond_to?(attr_name)
                    send(attr_name)
                  else
                    attr_config.default
                  end
          value = attr_config.process_value(value, self) if attr_config.respond_to?(:process_value)
          dep_attributes[attr_name] = value
        end
      end

      dep_attributes
    end

    def determine_option_name(component_type, init_args)
      dependency_builder = self.class.dependency_definitions[component_type]

      option_name = nil

      # Use when block if defined
      if dependency_builder.when_block
        result = instance_exec(init_args, &dependency_builder.when_block)
        if result.is_a?(Hash) && result[:option]
          option_name = result[:option]
          as_attr = result[:as]
          init_args = { as_attr => init_args } if as_attr && init_args
        end
      end

      # Detect option from user input
      if option_name.nil? && (init_args.is_a?(Hash) && init_args.keys.size == 1)
        if dependency_builder.option_configs.key?(init_args.keys.first)
          option_name = init_args.keys.first
          init_args = init_args[option_name] # Extract the inner value
        else
          default_option = dependency_builder.get_option(dependency_builder.default_option_name)
          raise ArgumentError, "Unknown #{component_type} option: #{init_args.keys.first}." unless default_option.only?
          unless default_option.attributes.keys.include?(init_args.keys.first)
            raise ArgumentError, "#{default_option.class_name} does not respond to #{init_args.keys.first}"
          end
        end
      end

      # Use default option if none determined
      option_name ||= dependency_builder.default_option_name

      [option_name, init_args]
    end

    def instantiate_dependency(option_config, dep_attributes)
      dependency_class = option_config.class_name
      dependency_instance = dependency_class.new(dep_attributes)
      dependency_instance.validate! if false # dependency_instance.respond_to?(:validate!)
      dependency_instance
    end

    def propagate_changes
      changed_attributes.each do |attr_name, _old_value|
        new_value = read_attribute(attr_name)
        propagate_attribute_change(attr_name, new_value)
      end

      # Clear the changes after propagation
      changes_applied
    end

    def propagate_attribute_change(attr_name, value)
      self.class.dependency_definitions.each do |component_type, _dependency_builder|
        dependency_instance = send(component_type)
        option_config = dependencies.dig(component_type, :option)
        next unless option_config

        bound_attrs = option_config.attributes.select do |_, attr_config|
          (attr_config.source == attr_name.to_sym) || (attr_config.name == attr_name.to_sym)
        end

        bound_attrs.each do |dep_attr_name, config_attr|
          block = config_attr.block.present? ? config_attr.block : proc { |att| att }
          if dependency_instance.respond_to?("#{dep_attr_name}=")
            dependency_instance.send("#{dep_attr_name}=",
                                     block.call(value))
          end
        end
      end
    end

    def dependency_injected?(component_type, value)
      dependency_builder = self.class.dependency_definitions[component_type]
      dependency_builder.option_configs.values.any? do |option|
        option_class = option.class_name
        value.is_a?(option_class)
      end
    end

    def dependencies
      @dependencies ||= {}
    end

    def validate_dependencies
      errors.clear
      self.class.dependency_definitions.keys.each do |component_type|
        dependency = send(component_type)

        # Only validate if the dependency responds to `valid?`
        next unless dependency.respond_to?(:valid?) && !dependency.valid?

        dependency.errors.each do |error|
          if error.is_a?(ActiveModel::Error)
            attribute = error.attribute
            message = error.message
          end
          errors.add("#{component_type}.#{attribute}", message)
        end
      end
      errors.none?
    end

    class ConfigAttr
      attr_reader :name, :default, :required, :source, :block

      def initialize(name, default: nil, required: false, source: nil, &block)
        @name = name.to_sym
        @default = default
        @required = required
        @source = source
        @block = block
      end

      def process_value(value, _context = nil)
        value = evaluate_value(value)
        value = evaluate_value(@default) if value.nil? && !@default.nil?
        value = @block.call(value) if @block && !value.nil?
        value
      end

      private

      def evaluate_value(value)
        value.is_a?(Proc) ? value.call : value
      end
    end

    class DependencyBuilder
      attr_reader :component_type, :option_configs, :when_block, :is_only

      def initialize(component_type)
        @component_type = component_type
        @option_configs = {}
        @default_option_name = nil
        @single_option = nil
        @is_only = false
      end

      # Support set_class and attribute for single-option dependencies
      def set_class(class_name)
        single_option.set_class(class_name)
        set_default_option_name(:default)
      end

      def bind_attribute(name, default: nil, required: false, source: nil, &block)
        single_option.bind_attribute(name, default: default, required: required, source: source, &block)
      end

      def get_option(name)
        @option_configs[name]
      end

      # For multi-option dependencies
      def option(name, &block)
        option_builder = OptionBuilder.new(name)
        option_builder.instance_eval(&block)
        @option_configs[name] = option_builder
        set_default_option_name(name) if option_builder.is_default
      end

      def default_option_name
        @default_option_name || (@single_option ? :default : nil)
      end

      def when(&block)
        @when_block = block
      end

      def single_option
        @single_option ||= begin
          option_builder = OptionBuilder.new(:default)
          option_builder.only
          @option_configs[:default] = option_builder
          set_default_option_name(:default)
          option_builder
        end
      end

      def only?
        @is_only == true
      end

      private

      def set_default_option_name(name)
        if @default_option_name && @default_option_name != name
          raise ArgumentError, "Multiple default options found for #{@component_type}"
        end

        @default_option_name = name
      end
    end

    class OptionBuilder
      attr_reader :name, :class_name, :attributes, :is_default, :is_only

      def initialize(name)
        @name = name
        @attributes = {}
        @is_default = false
      end

      def set_class(name)
        if name.is_a?(Class)
          @class_name = name
        elsif name.is_a?(String)
          @class_name = name.constantize
        else
          raise "Class name #{name} must be a string or class. Cannot find #{name}."
        end
      end

      def bind_attribute(name, default: nil, required: false, source: nil, &block)
        attr = ConfigAttr.new(name, default: default, required: required, source: source, &block)
        @attributes[name.to_sym] = attr
      end

      def default
        @is_default = true
      end

      def only
        @is_only = true
      end

      def only?
        @is_only == true
      end
    end
  end
end
