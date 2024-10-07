# GlueGun::DSL

**All the magic you love from ActiveRecord/ActiveModel, plus dependency-management as a first-class citizen.**

GlueGun::DSL enhances ActiveModel by introducing powerful dependency injection capabilities directly into your Ruby objects. Whether you're working with **ActiveRecord** models **or Plain Old Ruby Objects** (POROs), GlueGun::DSL allows you to manage interchangeable dependencies with ease, handling complex relationships between components while maintaining clean and maintainable code.

## Table of Contents

- [Introduction](#introduction)
- [Getting Started](#getting-started)
  - [Using with ActiveRecord Models](#using-with-activerecord-models)
  - [Using with POROs](#using-with-poros)
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

## Introduction

GlueGun::DSL extends ActiveModel by making dependency injection a first-class feature. While ActiveModel provides a robust framework for attributes, validations, and type casting, GlueGun::DSL builds upon it to simplify the management of complex dependencies between components. It's designed to help you write cleaner, more modular code by allowing you to define and configure dependencies directly within your models or Ruby objects.

Whether you're enhancing an **ActiveRecord** model or working with a **PORO**, GlueGun::DSL provides the tools to manage dependencies effectively.

## Getting Started

To use GlueGun::DSL in your class, include it after requiring the gem. GlueGun::DSL is compatible with both **ActiveRecord** models and **Plain Old Ruby Objects (POROs)**.

### Using with ActiveRecord Models

When using GlueGun::DSL with **ActiveRecord**, you can leverage ActiveRecord's powerful ORM features alongside GlueGun's dependency injection.

```ruby
# app/models/user.rb
require 'glue_gun'

class User < ApplicationRecord
  include GlueGun::DSL

  attribute :role, :string, default: 'member'

  define_dependency :mailer do |dependency|
    dependency.option :smtp do |option|
      option.set_class 'SmtpMailer'
      option.attribute :server, default: 'smtp.example.com'
      option.attribute :port, default: 587
    end

    dependency.option :sendgrid do |option|
      option.set_class 'SendGridMailer'
      option.attribute :api_key, required: true
    end

    dependency.default_option_name = :smtp
  end

  validates :role, presence: true
end

# Usage
user = User.new(email: 'user@example.com')
user.mailer # => Instance of SmtpMailer with server: 'smtp.example.com', port: 587

user = User.new(email: 'user@example.com', mailer: {sendgrid: {api_key: "12345"}})
user.mailer # => Instance of SendGridMailer with api_key set
```

### Using with POROs

GlueGun::DSL is equally powerful when used with Plain Old Ruby Objects (POROs), allowing you to build flexible and testable classes without the overhead of ActiveRecord.

```ruby
# app/services/payment_processor.rb
require 'glue_gun'

class PaymentProcessor
  include GlueGun::DSL

  attribute :amount, :integer
  attribute :currency, :string, default: 'USD'

  define_dependency :gateway do |dependency|
    dependency.option :stripe do |option|
      option.set_class 'StripeGateway'
      option.attribute :api_key, required: true
    end

    dependency.option :paypal do |option|
      option.set_class 'PaypalGateway'
      option.attribute :client_id, required: true
      option.attribute :client_secret, required: true
    end

    dependency.default_option_name = :stripe
  end

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
end

# Usage
processor = PaymentProcessor.new(amount: 1000, gateway: { paypal: { client_id: 'abc', client_secret: 'xyz' } })
processor.gateway # => Instance of PaypalGateway with client_id: 'abc', client_secret: 'xyz'
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

## Dependency Injection

One of the key differences between GlueGun::DSL and ActiveModel is the introduction of dependency injection as a core feature. GlueGun::DSL allows you to define dependencies that your class relies on, configure them flexibly, and even bind attributes between your class and its dependencies.

## Defining Dependencies

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

# Usage:
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

# Usage:
instance = MyClass.new(database: { mysql: { host: 'localhost' } })
instance.database # => Instance of MySQLDatabase

instance = MyClass.new(database: { postgresql: { host: 'localhost' } })
instance.database # => Instance of PostgreSQLDatabase
```

### Dynamic Dependency Resolution with `when`

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

# Usage:
instance = MyClass.new(storage: 's3://my-bucket')
instance.storage # => Instance of S3Storage

instance = MyClass.new(storage: '/data/files')
instance.storage # => Instance of LocalStorage
```

## Attribute Binding Between Components

Attributes can be bound between your class and its dependencies using the `source` option. This ensures that when an attribute changes in the parent class, it automatically updates in the dependency.

```ruby
attribute :root_path, :string, default: '/app/root'

define_dependency :file_manager do |dependency|
  dependency.set_class 'FileManager'
  dependency.attribute :base_path, source: :root_path
end

# Usage:
instance = MyClass.new
instance.root_path = '/new/root'
instance.file_manager.base_path # => '/new/root'
```

## Inheritance and Overrides

GlueGun::DSL supports inheritance, allowing subclasses to inherit attributes and dependencies from parent classes and override them as needed.

```ruby
class Dataset
  include GlueGun::DSL

  define_dependency :datasource do |dependency|
    dependency.option :s3 do |option|
      option.set_class "S3Datasource"
      option.attribute :bucket, required: true
    end
  end
end

class SpecializedDataset < Dataset
  attribute :special_feature, :boolean, default: true

  # Override the datasource dependency with a different configuration
  define_dependency :datasource do |dependency|
    dependency.option :azure do |option|
      option.set_class "AzureDatasource"
      option.attribute :container, required: true
    end
  end
end
```

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

## Defining Attributes

GlueGun::DSL leverages ActiveModel::Attributes to define attributes with type casting, default values, and validations, just like you're used to.

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

Use ActiveModel::Validations to add validations to your attributes:

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

## Comparison with ActiveModel

While ActiveModel provides a solid foundation for defining attributes, validations, and type casting, it lacks built-in support for dependency injection or managing complex dependencies between components.

### Key Differences and Enhancements with GlueGun::DSL:

- **First-Class Dependency Injection**: Easily define and configure dependencies directly within your models or Ruby objects, making your code more modular and testable.
- **Dynamic Dependency Resolution**: Use the `when` block to select dependencies based on runtime input, providing flexibility in how dependencies are configured and used.
- **Attribute Binding Between Components**: Synchronize attribute values between your class and its dependencies seamlessly, reducing boilerplate code and potential for errors.
- **Enhanced DSL**: Maintain the familiar syntax and features of ActiveModel while gaining powerful new capabilities.
- **Compatibility with ActiveRecord and POROs**: GlueGun::DSL works seamlessly with ActiveRecord models and can be used with any Ruby object, providing flexibility based on your application's architecture.

By incorporating these features, GlueGun::DSL allows you to manage complex configurations and relationships within your models or Ruby objects more effectively than with ActiveModel alone.

## Contributing

We welcome contributions to GlueGun::DSL! To contribute:

1. **Fork the repository** on GitHub.
2. **Create a new branch** with your feature or bug fix.
3. **Write tests** for your changes.
4. **Submit a pull request** with a detailed explanation.

Please ensure your code follows the project's coding standards and passes all tests. To test against different versions of ActiveModel:

```bash
bundle exec appraisal activemodel-6 guard
bundle exec appraisal activemodel-7 guard
```

## License

GlueGun::DSL is released under the MIT License.

---

**Enjoy Using GlueGun::DSL!**

With GlueGun::DSL, you can supercharge your Ruby classes by seamlessly integrating dependency injection alongside the familiar ActiveModel features. Whether you're enhancing ActiveRecord models or building simple POROs, GlueGun::DSL provides the tools to manage your components effectively.

For more examples and detailed documentation, please visit our [GitHub repository](https://github.com/your_username/glue_gun_dsl).

_Note: Replace `your_username` with your actual GitHub username and ensure the `LICENSE.txt` file is included in your repository._

---
