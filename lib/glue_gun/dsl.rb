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

      # Overriding ActiveModel.assign_attributes to ensure change propagation to dependencies
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

        if attribute_definitions.keys.include?(:root_dir) && attribute_definitions.dig(:root_dir, :options,
                                                                                       :default).nil?
          normal_attributes.reverse_merge!(root_dir: detect_root_dir)
        end

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

      def dependency(component_type, options = {}, factory_class = nil, &block)
        if options.is_a?(Class)
          factory_class = options
          options = {}
        end

        dependency_builder = DependencyBuilder.new(component_type, options)

        if factory_class.present?
          dependency_builder.set_factory_class(factory_class)
        else
          dependency_builder.instance_eval(&block)
        end
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
      self.class.dependency_definitions.each do |component_type, definition|
        value = attributes[component_type] || self.class.hardcoded_dependencies[component_type]
        instance_variable_set("@#{component_type}", initialize_dependency(component_type, value, definition))
      end
    end

    def initialize_dependency(component_type, init_args = nil, definition = nil)
      definition ||= self.class.dependency_definitions[component_type]
      is_array = init_args.is_a?(Array)
      is_hash = definition.is_hash?(init_args)

      if init_args.nil? && definition.default_option_name.nil?
        return nil if definition.lazy?
        if definition.when_block.nil?
          raise "No default option or when block present for component_type #{component_type}. Don't know how to build!"
        end
      end

      if is_array
        dep = []
        config = []
        Array(init_args).each do |args|
          d, c = definition.initialize_single_dependency(args, self)
          dep.push(d)
          config.push(c)
        end
      elsif is_hash
        dep = {}
        config = {}
        definition.validate_hash_dependencies(init_args)

        init_args.each do |key, args|
          d, c = definition.initialize_single_dependency(args, self)
          dep[key] = d
          config[key] = c
        end
      else
        dep, config = definition.initialize_single_dependency(init_args, self)
      end

      dependencies[component_type] = {
        instance: dep,
        option: config
      }

      dep
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
      self.class.dependency_definitions.each do |component_type, _builder|
        dependency_instance = send(component_type)

        if dependency_instance.is_a?(Array)
          option_config = dependencies.dig(component_type, :option)

          dependency_instance.zip(option_config).each do |dep, opt|
            propagate_attribute_to_instance(attr_name, value, dep, opt)
          end
        elsif dependency_instance.is_a?(Hash)
          option_config = dependencies.dig(component_type, :option)

          dependency_instance.each do |key, dep|
            propagate_attribute_to_instance(attr_name, value, dep, option_config[key])
          end
        else
          option_config = dependencies.dig(component_type, :option)
          next unless option_config

          propagate_attribute_to_instance(attr_name, value, dependency_instance, option_config)
        end
      end
    end

    def propagate_attribute_to_instance(attr_name, value, dependency_instance, option_config)
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

    def dependencies
      @dependencies ||= {}
    end

    def inspect
      "#<#{self.class} #{attributes.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")}>"
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
      attr_reader :component_type, :option_configs, :when_block, :is_only, :factory_class, :lazy, :parent

      def initialize(component_type, options)
        @component_type = component_type
        @option_configs = {}
        @default_option_name = nil
        @single_option = nil
        @is_only = false
        @lazy = options.key?(:lazy) ? options.dig(:lazy) : true
      end

      def set_factory_class(factory_class)
        @factory_class = factory_class
      end

      def builder
        if factory?
          factory_instance = factory_class.new
          dep_defs = factory_instance.dependency_definitions
          dep_defs[dep_defs.keys.first]
        else
          self
        end
      end

      def get_option_configs
        builder.option_configs
      end

      def allowed_configurations
        get_option_configs.keys
      end

      def allowed_classes
        get_option_configs.values
      end

      def factory?
        @factory_class.present?
      end

      def builder?
        !factory?
      end

      def lazy?
        @lazy == true
      end

      def is_hash?(init_args)
        return false unless init_args.is_a?(Hash)

        allowed_configs = allowed_configurations
        return false if allowed_configs.count == 1 && allowed_configs == [:default]

        if init_args.key?(:option_name)
          allowed_configs.exclude?(init_args[:option_name])
        else
          init_args.keys.none? { |k| allowed_configs.include?(k) }
        end
      end

      def initialize_factory_dependency(init_args, instance)
        builder.initialize_single_dependency(init_args, instance)
      end

      def initialize_builder_dependency(init_args, instance)
        if init_args && init_args.is_a?(Hash) && init_args.key?(:option_name)
          option_name = init_args[:option_name]
          init_args = init_args[:value]
        else
          option_name, init_args = determine_option_name(init_args, instance)
        end

        option_config = option_configs[option_name]

        raise ArgumentError, "Unknown #{component_type} option '#{option_name}'" unless option_config

        [instantiate_dependency(option_config, init_args, instance), option_config]
      end

      def initialize_single_dependency(init_args, instance)
        if dependency_injected?(init_args)
          dep = init_args
          option_config = injected_dependency(init_args)
        elsif factory?
          dep, option_config = initialize_factory_dependency(init_args, instance)
        else
          dep, option_config = initialize_builder_dependency(init_args, instance)
        end

        [dep, option_config]
      end

      def build_dependency_attributes(option_config, dep_attributes, parent)
        option_config.attributes.each do |attr_name, attr_config|
          if dep_attributes.key?(attr_name)
            dep_attributes[attr_name]
          else
            value = if attr_config.source && parent.respond_to?(attr_config.source)
                      parent.send(attr_config.source)
                    elsif parent.respond_to?(attr_name)
                      parent.send(attr_name)
                    else
                      attr_config.default
                    end
            value = attr_config.process_value(value, self) if attr_config.respond_to?(:process_value)
            dep_attributes[attr_name] = value
          end
        end

        dep_attributes.deep_compact
      end

      def determine_option_name(init_args, instance)
        option_name = nil

        # Use when block if defined
        if when_block
          result = instance.instance_exec(init_args, &when_block)
          if result.is_a?(Hash) && result[:option]
            option_name = result[:option]
            as_attr = result[:as]
            init_args = { as_attr => init_args } if as_attr && init_args
          end
        end

        # Detect option from user input
        if option_name.nil? && (init_args.is_a?(Hash) && init_args.keys.size == 1)
          if option_configs.key?(init_args.keys.first)
            option_name = init_args.keys.first
            init_args = init_args[option_name] # Extract the inner value
          else
            default_option = get_option(default_option_name)
            unless default_option.only?
              raise ArgumentError,
                    "Unknown #{component_type} option: #{init_args.keys.first}."
            end
            unless default_option.attributes.keys.include?(init_args.keys.first)
              raise ArgumentError, "#{default_option.class_name} does not respond to #{init_args.keys.first}"
            end
          end
        end

        # Use default option if none determined
        option_name ||= default_option_name

        [option_name, init_args]
      end

      def instantiate_dependency(option_config, init_args, parent)
        dep_attributes = init_args.is_a?(Hash) ? init_args : {}

        # Build dependency attributes, including sourcing from parent
        dep_attributes = build_dependency_attributes(option_config, dep_attributes, parent)

        if dep_attributes.key?(:id)
          raise ArgumentError,
                "cannot bind attribute 'id' between #{parent.class.name} and #{option_config.class_name}. ID is reserved for primary keys in Ruby on Rails"
        end
        dependency_class = option_config.class_name
        dependency_class.new(dep_attributes)
      end

      def injected_dependency(value)
        allowed_classes.detect do |option|
          option_class = option.class_name
          value.is_a?(option_class)
        end
      end

      def dependency_injected?(value)
        injected_dependency(value).present?
      end

      def validate_hash_dependencies(init_args)
        allowed_configs = allowed_configurations

        init_args.each do |_named_key, configuration|
          next unless configuration.is_a?(Hash)

          key = configuration.keys.first
          if key.nil? || allowed_configs.exclude?(key)
            raise ArgumentError,
                  "Unknown #{component_type} option: #{init_args.keys.first}."
          end
        end
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
        if factory?
          builder.default_option_name
        else
          @default_option_name || (@single_option ? :default : nil)
        end
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
