# GlueGun::DSL

**All the helpers you know and love from ActiveModel, plus dependency injection as a first-class citizen.**

GlueGun::DSL enhances `ActiveModel` by introducing powerful dependency injection capabilities directly into your Ruby objects. It allows you to manage interchangable dependencies with ease, managing complex relationships between components while maintaining clean and maintainable code.

```ruby

class Model
  include GlueGun::DSL

  define_dependency :database do |dependency|
   dependency.option :mysql do |option|
     option.default # set a default option!
     option.set_class 'MySQLDatabase'
     option.attribute :host, required: true
     option.attribute :port, default: 3306
   end

   dependency.option :postgresql do |option|
     option.set_class 'PostgreSQLDatabase'
     option.attribute :host, required: true
     option.attribute :port, default: 5432
   end
  end
end

instance = Model.new(database: { postgres: { host: "localhost" } })
instance.database # is a PostgreSQLDatabase instance with host: localhost, port: 5432
```

---

## Table of Contents

- [Introduction](#introduction)
- [Getting Started](#getting-started)
- [Installation](#installation)
- [Dependency Injection](#dependency-injection)
  - [Defining Dependencies](#defining-dependencies)
  - [Single-Option Dependencies](#single-option-dependencies)
  - [Multi-Option Dependencies](#multi-option-dependencies)
  - [Dynamic Dependency Resolution with `when`](#dynamic-dependency-resolution-with-when)
  - [Attribute Binding Between Components](#attribute-binding-between-components)
- [Inheritance and Overrides](#inheritance-and-overrides)
- [Complete Examples](#complete-examples)
  - [Building a Complex Data Pipeline](#building-a-complex-data-pipeline)
- [Defining Attributes](#defining-attributes)
  - [Basic Usage](#basic-usage)
  - [Default Values](#default-values)
  - [Type Casting](#type-casting)
  - [Validations](#validations)
  - [Custom Setters and Getters](#custom-setters-and-getters)
- [Comparison with ActiveModel](#comparison-with-activemodel)
- [Contributing](#contributing)
- [License](#license)

---

## Introduction

GlueGun::DSL extends `ActiveModel` by making dependency injection a first-class feature. While `ActiveModel` provides a robust framework for attributes, validations, and type casting, GlueGun::DSL builds upon it to simplify the management of complex dependencies between components. It's designed to help you write cleaner, more modular code by allowing you to define and configure dependencies directly within your models.

---

## Getting Started

To use GlueGun::DSL in your class, include it after requiring the gem:

```ruby
require 'glue_gun'

class MyClass
  include GlueGun::DSL

  # Define attributes and dependencies here
end
```

This inclusion provides all the features of `ActiveModel`, plus the enhanced dependency injection capabilities of GlueGun::DSL.

---

## Dependency Injection

One of the key differences between GlueGun::DSL and `ActiveModel` is the introduction of dependency injection as a core feature. GlueGun::DSL allows you to define dependencies that your class relies on, configure them flexibly, and even bind attributes between your class and its dependencies.

### Defining Dependencies

Use `define_dependency` to declare a dependency:

```ruby
define_dependency :logger do |dependency|
  dependency.set_class 'Logger'
  dependency.attribute :level, default: 'INFO'
end
```

This defines a `logger` dependency that can be accessed via `instance.logger`.

### Single-Option Dependencies

For simple dependencies without multiple configurations:

```ruby
define_dependency :cache do |dependency|
  dependency.set_class 'MemoryCache'
  dependency.attribute :size, default: 1024
end
```

Usage:

```ruby
instance = MyClass.new
instance.cache.size # => 1024
```

### Multi-Option Dependencies

When a dependency can have multiple implementations or configurations, define options within the dependency:

```ruby
define_dependency :database do |dependency|
  dependency.option :mysql do |option|
    option.set_class 'MySQLDatabase'
    option.attribute :host, required: true
    option.attribute :port, default: 3306
  end

  dependency.option :postgresql do |option|
    option.set_class 'PostgreSQLDatabase'
    option.attribute :host, required: true
    option.attribute :port, default: 5432
  end

  dependency.default_option_name = :mysql
end
```

Usage:

```ruby
instance = MyClass.new(database: { mysql: { host: 'localhost' } })
instance.database # Instance of MySQLDatabase

instance = MyClass.new(database: { postgresql: { host: 'localhost' } })
instance.database # Instance of PostgreSQLDatabase
```

### Sexy Interfaces With The `when` Block

Use the `when` block to dynamically determine which dependency option to use based on input:

```ruby
define_dependency :storage do |dependency|
  dependency.option :s3 do |option|
    option.set_class 'S3Storage'
    option.attribute :bucket_name, required: true
  end

  dependency.option :local do |option|
    option.set_class 'LocalStorage'
    option.attribute :directory, required: true
  end

  dependency.when do |dep|
    case dep
    when /^s3:\/\//
      { option: :s3, as: :bucket_name }
    when /^\/\w+/
      { option: :local, as: :directory }
    end
  end
end
```

Usage:

```ruby
instance = MyClass.new(storage: 's3://my-bucket')
instance.storage # Instance of S3Storage

instance = MyClass.new(storage: '/data/files')
instance.storage # Instance of LocalStorage
```

### Attribute Binding Between Components

Attributes can be bound between your class and its dependencies using the `source` option. This ensures that when an attribute changes in the parent class, it automatically updates in the dependency.

```ruby
attribute :root_path, :string, default: '/app/root'

define_dependency :file_manager do |dependency|
  dependency.set_class 'FileManager'
  dependency.attribute :base_path, source: :root_path
end
```

When `root_path` is updated, `file_manager.base_path` reflects the change:

```ruby
instance = MyClass.new
instance.root_path = '/new/root'
instance.file_manager.base_path # => '/new/root'
```

---

## Inheritance and Overrides

GlueGun::DSL supports inheritance, allowing subclasses to inherit attributes and dependencies from parent classes and override them as needed.

```ruby
class Dataset
  include GlueGun::DSL

  define_dependency :datasource do |dependency|
    dependency.option :s3 do |option|
      option.set_class "S3Datasource"
      option.attribute
    end
  end
end

class SpecializedService < BaseService
  attribute :special_feature, :boolean, default: true

  # Override the logger dependency with different configuration
  logger :logger, level: 'DEBUG'
end
```

---

## Complete Examples

### Building a Complex Data Pipeline

Below is an example of building a complex data pipeline using GlueGun::DSL, showcasing how to define attributes, dependencies, and dynamic configurations.

```ruby
require 'glue_gun'

module DataPipeline
  class Dataset
    include GlueGun::DSL

    # Define attributes
    attribute :name, :string
    attribute :batch_size, :integer, default: 1000
    attribute :data_dir, :string, default: File.join(Dir.pwd, 'dataset')

    # Define a data source dependency with multiple options
    define_dependency :datasource do |dependency|
      dependency.option :csv do |option|
        option.set_class 'CsvDatasource'
        option.attribute :file_path, source: :data_dir
      end

      dependency.option :api do |option|
        option.set_class 'ApiDatasource'
        option.attribute :endpoint
        option.attribute :api_key
      end

      # Dynamically determine the datasource based on input
      dependency.when do |dep|
        case dep
        when String
          if dep.start_with?('http')
            { option: :api, as: :endpoint }
          else
            { option: :csv, as: :file_path }
          end
        end
      end

      dependency.default_option_name = :csv
    end

    # Define a processor dependency
    define_dependency :processor do |dependency|
      dependency.set_class 'DataProcessor'
      dependency.attribute :batch_size, source: :batch_size
    end

    # Example methods
    def load_data
      datasource.fetch_data
    end

    def process_data
      processor.process(load_data)
    end
  end
end

# Usage Example
dataset = DataPipeline::Dataset.new(
  name: 'Sales Data',
  datasource: 'sales.csv',
  batch_size: 500
)

dataset.process_data
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'glue_gun_dsl'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install glue_gun_dsl
```

---

## Defining Attributes

GlueGun::DSL leverages `ActiveModel::Attributes` to define attributes with type casting, default values, and validations, just like you're used to.

### Basic Usage

Define attributes using the `attribute` method:

```ruby
class User
  include GlueGun::DSL

  attribute :name, :string
  attribute :email, :string
end
```

### Default Values

You can specify default values for attributes:

```ruby
attribute :role, :string, default: 'member'
```

### Type Casting

Attributes are automatically type-cast based on the specified type:

```ruby
attribute :age, :integer
attribute :active, :boolean, default: true
```

### Validations

Use `ActiveModel::Validations` to add validations to your attributes:

```ruby
attribute :email, :string
validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
```

### Custom Setters and Getters

Define custom logic for attribute setters and getters:

```ruby
attribute :salary, :integer

def salary=(value)
  super(value.to_i * 100)
end

def salary
  super / 100
end
```

---

---

## Comparison with ActiveModel

While `ActiveModel` provides a solid foundation for defining attributes, validations, and type casting, it lacks built-in support for dependency injection or managing complex dependencies between components.

**Key Differences and Enhancements with GlueGun::DSL:**

- **First-Class Dependency Injection**: Easily define and configure dependencies directly within your models, making your code more modular and testable.
- **Dynamic Dependency Resolution**: Use the `when` block to select dependencies based on runtime input, providing flexibility in how dependencies are configured and used.
- **Attribute Binding Between Components**: Synchronize attribute values between your class and its dependencies seamlessly, reducing boilerplate code and potential for errors.
- **Enhanced DSL**: Maintain the familiar syntax and features of `ActiveModel` while gaining powerful new capabilities.

By incorporating these features, GlueGun::DSL allows you to manage complex configurations and relationships within your models more effectively than with `ActiveModel` alone.

---

## Contributing

We welcome contributions to GlueGun::DSL! To contribute:

1. **Fork** the repository on GitHub.
2. **Create** a new branch with your feature or bug fix.
3. **Write** tests for your changes.
4. **Submit** a pull request with a detailed explanation.

Please ensure your code follows the project's coding standards and passes all tests. To test against different versions of ActiveModel:

```
bundle exec appraisal activemodel-6 guard
bundle exec appraisal activemodel-7 guard
```

---

## License

GlueGun::DSL is released under the [MIT License](LICENSE.txt).

---

## Enjoy Using GlueGun::DSL!

With GlueGun::DSL, you can supercharge your Ruby classes by seamlessly integrating dependency injection alongside the familiar `ActiveModel` features. Whether you're building simple applications or complex systems, GlueGun::DSL provides the tools to manage your components effectively.

---

For more examples and detailed documentation, please visit our [GitHub repository](https://github.com/your_username/glue_gun_dsl).

---

**Note:** Replace `your_username` with your actual GitHub username and ensure the `LICENSE.txt` file is included in your repository.
