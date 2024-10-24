require "pry"
require "spec_helper"

PROJECT_ROOT = Pathname.new(File.expand_path("..", __dir__))

require "pathname"

class Pathname
  def append(folder)
    dir = cleanpath
    dir = dir.join(folder) unless basename.to_s == folder
    dir
  end
end

RSpec.describe GlueGun::DSL do
  describe "ActiveModel integration" do
    # Mocking necessary classes for the tests
    class NoOp
      include ActiveModel::Model
      include ActiveModel::Attributes
    end

    module Test
      module Data
        class PreprocessingSteps
          include GlueGun::DSL

          attribute :preprocessing_steps, :hash
          attribute :directory, :string
          attribute :complex_chain, :string
          attribute :custom_field, :string
        end

        class SyncedDir
          include GlueGun::DSL
          attribute :root_dir, :string
          attribute :s3_bucket, :string
        end

        module Datasource
          class S3Datasource
            include GlueGun::DSL

            attribute :s3_bucket, :string
            attribute :s3_prefix, :string
            attribute :root_dir, :string
            attribute :s3_access_key_id, :string
            attribute :s3_secret_access_key, :string
            attribute :polars_args, :hash, default: {}

            validates :s3_bucket, :s3_access_key_id, :s3_secret_access_key, presence: true

            dependency :synced_directory do |dep|
              dep.set_class Test::Data::SyncedDir
              dep.bind_attribute :root_dir do |value|
                Pathname.new(value).append("secrets").to_s
              end
              dep.bind_attribute :s3_bucket
            end
          end

          class FileDatasource
            include ActiveModel::Model
            include ActiveModel::Attributes
            attribute :root_dir, :string

            validates :root_dir, presence: true
          end

          class PolarsDatasource
            include GlueGun::DSL
            attribute :df
            attribute :complex_chain
            validates :df, presence: true
          end
        end
      end
    end

    class FactoryWithDefault
      include GlueGun::DSL

      dependency :datasource do |dependency|
        dependency.option :no_op do |option|
          option.default
          option.set_class NoOp
        end

        dependency.option :s3 do |option|
          option.set_class Test::Data::Datasource::S3Datasource
          option.bind_attribute :root_dir
          option.bind_attribute :s3_bucket, required: true
          option.bind_attribute :s3_access_key_id, default: "12345"
          option.bind_attribute :polars_args, required: true, default: {}
        end

        dependency.option :directory do |option|
          option.set_class Test::Data::Datasource::FileDatasource
          option.bind_attribute :root_dir do |value|
            File.join(value, "bingo/bangos")
          end
        end

        dependency.option :polars do |option|
          option.set_class Test::Data::Datasource::PolarsDatasource
          option.bind_attribute :complex_chain do |value|
            "#{value} and super cool"
          end
        end

        dependency.when do |dep|
          case dep
          when Polars::DataFrame
            { option: :polars, as: :df }
          when String
            { option: :directory, as: :root_dir }
          end
        end
      end
    end

    class DatasourceFactory
      include GlueGun::DSL

      dependency :datasource do |dependency|
        dependency.option :s3 do |option|
          option.set_class Test::Data::Datasource::S3Datasource
          option.bind_attribute :root_dir
          option.bind_attribute :s3_bucket, required: true
          option.bind_attribute :s3_access_key_id, default: "12345"
          option.bind_attribute :polars_args, required: true, default: {}
        end

        dependency.option :directory do |option|
          option.set_class Test::Data::Datasource::FileDatasource
          option.bind_attribute :root_dir do |value|
            File.join(value, "bingo/bangos")
          end
        end

        dependency.option :polars do |option|
          option.set_class Test::Data::Datasource::PolarsDatasource
          option.bind_attribute :complex_chain do |value|
            "#{value} and super cool"
          end
        end

        dependency.when do |dep|
          case dep
          when Polars::DataFrame
            { option: :polars, as: :df }
          when String
            { option: :directory, as: :root_dir }
          end
        end
      end
    end

    class PolarsHelper
      include GlueGun::DSL
    end

    class S3Helper
      include GlueGun::DSL
    end

    class DirectoryHelper
      include GlueGun::DSL
    end

    class NoopHelper
      include GlueGun::DSL
    end

    # Define SomethingCool class using the new GlueGun::DSL
    class SomethingCool
      include GlueGun::DSL

      attribute :id, :string, default: "Default Name"
      attribute :age, :integer
      validates :age, presence: true
      attribute :root_dir, :string

      attribute :complex_chain, :string
      def complex_chain=(value)
        super("#{value} is cool")
      end

      attribute :processed_attr, :integer, default: 0
      attribute :polars_args, :hash, default: {}

      def processed_attr=(value)
        super(value.to_i * 2)
      end

      attribute :preprocessing_steps, :hash, default: {}

      dependency :preprocessor do |dependency|
        dependency.set_class Test::Data::PreprocessingSteps
        dependency.bind_attribute :directory, source: :root_dir
        dependency.bind_attribute :complex_chain do |value|
          "#{value} and rocks my socks"
        end
      end

      dependency :datasource do |dependency|
        dependency.option :no_op do |option|
          option.default
          option.set_class NoOp
        end

        dependency.option :s3 do |option|
          option.set_class Test::Data::Datasource::S3Datasource
          option.bind_attribute :root_dir
          option.bind_attribute :s3_bucket, required: true
          option.bind_attribute :s3_access_key_id, default: "12345"
          option.bind_attribute :polars_args, required: true, default: {}
        end

        dependency.option :directory do |option|
          option.set_class Test::Data::Datasource::FileDatasource
          option.bind_attribute :root_dir do |value|
            File.join(value, "bingo/bangos")
          end
        end

        dependency.option :polars do |option|
          option.set_class Test::Data::Datasource::PolarsDatasource
          option.bind_attribute :complex_chain do |value|
            "#{value} and super cool"
          end
        end

        dependency.when do |dep|
          case dep
          when Polars::DataFrame
            { option: :polars, as: :df }
          when String
            { option: :directory, as: :root_dir }
          end
        end
      end

      dependency :datasource_helper, lazy: false do |dep|
        dep.option :no_op do |option|
          option.set_class NoopHelper
        end

        dep.option :s3 do |option|
          option.set_class S3Helper
        end

        dep.option :directory do |option|
          option.set_class DirectoryHelper
        end

        dep.option :polars do |option|
          option.set_class PolarsHelper
        end

        dep.when do |_dep|
          case datasource
          when Test::Data::Datasource::PolarsDatasource
            { option: :polars }
          when Test::Data::Datasource::FileDatasource
            { option: :directory }
          when Test::Data::Datasource::S3Datasource
            { option: :s3 }
          when NoOp
            { option: :no_op }
          end
        end
      end
    end

    class ChildClass < SomethingCool
      datasource :s3, s3_bucket: "my-bucket", s3_access_key_id: "12345", s3_secret_access_key: "67890"
      attribute :child_attr, :string, default: "Child Attr"
    end

    let(:s3_attrs) do
      {
        s3: {
          s3_bucket: "my-bucket",
          s3_access_key_id: "12345",
          s3_secret_access_key: "67890"
        }
      }
    end

    let(:test_class) { SomethingCool }
    let(:child_class) { ChildClass }
    describe "Attributes" do
      it "defines an attribute with a default on dependencies" do
        polars_args = { dtypes: { a: "float" } }
        instance = test_class.new(age: 30, polars_args: { dtypes: { a: "float" } },
                                  datasource: { s3: { s3_bucket: "default-bucket", s3_secret_access_key: "456" } })
        expect(instance.datasource.s3_access_key_id).to eq "12345"
        expect(instance.datasource.polars_args).to eq(polars_args)
      end

      it "defines picklist" do
        class Picklist
          include GlueGun::DSL

          attribute :fruits, :string
          validates :fruits, presence: true, inclusion: { in: %w[apple banana pear] }
        end

        a = Picklist.new(fruits: "apple")
        b = Picklist.new(fruits: "pear")
        expect(a.fruits).to eq "apple"
        expect(a).to be_valid
        expect(b.fruits).to eq "pear"
        expect(b).to be_valid
        c = Picklist.new(fruits: "raspberry")
        expect(c).to_not be_valid
      end

      it "defines conditional picklist" do
        class ConditionalPicklist
          include GlueGun::DSL

          attribute :task, :string
          validates :task, presence: true, inclusion: { in: %w[regression classification] }

          attribute :metrics, :string
          validate :validate_metrics

          def validate_metrics
            valid_options = case task
                            when "regression"
                              %w[mae mse rmse r2]
                            when "classification"
                              %w[accuracy precision f1 roc_auc]
                            else
                              []
                            end
            return if valid_options.include?(metrics)

            errors.add(:metrics, "#{metrics} is not an allowed metric for task #{task}")
          end
        end

        a = ConditionalPicklist.new(task: "regression", metrics: "rmse")
        expect(a).to be_valid
        b = ConditionalPicklist.new(task: "classification", metrics: "accuracy")
        expect(b).to be_valid
        c = ConditionalPicklist.new(task: "regression", metrics: "accuracy")
        expect(c).to_not be_valid
        expect(c.errors[:metrics]).to include("accuracy is not an allowed metric for task regression")
      end

      it "uses validations" do
        invalid_inst = test_class.new(datasource: s3_attrs)
        expect(invalid_inst).to_not be_valid
        expect(invalid_inst.errors.to_hash).to eq({ age: ["can't be blank"] })
      end

      it "processes attributes with a block" do
        instance = test_class.new(age: 30, processed_attr: "5", datasource: s3_attrs)
        expect(instance.processed_attr).to eq(10)
      end

      it "automatically sets root_dir default value and allows override" do
        instance = test_class.new(age: 30, datasource: s3_attrs)
        expect(instance.root_dir).to eq PROJECT_ROOT.join("spec").to_s

        instance = test_class.new(age: 50, datasource: s3_attrs, root_dir: PROJECT_ROOT)
        expect(instance.root_dir).to eq PROJECT_ROOT.to_s
      end

      it "errors when receiving an attribute that it does not expect" do
        expect do
          test_class.new(age: 30, datasource: s3_attrs, made_up_nonsense: true)
        end.to raise_error(ActiveModel::UnknownAttributeError)
      end

      it "errors when receiving an attribute that it does not expect for its dependencies" do
        class ExampleDep
          include ActiveModel::Model
          include ActiveModel::Attributes

          attribute :valid
        end

        class Example
          include GlueGun::DSL
          dependency :dep do |dep|
            dep.set_class ExampleDep
            dep.bind_attribute :valid
          end
        end

        example = Example.new(dep: { valid: true })
        expect(example.dep.valid).to eq true

        expect do
          Example.new(dep: { invalid: true })
        end.to raise_error(ActiveModel::UnknownAttributeError, /unknown attribute 'invalid'/)
      end
    end

    describe "Attribute binding" do
      it "does not bind the id attribute" do
        class Mistake
          include GlueGun::DSL
          attribute :id
        end

        class UhOh < ActiveRecord::Base
          include GlueGun::DSL

          dependency :dep do |dep|
            dep.set_class Mistake
            dep.bind_attribute :id
          end
        end

        expect do
          UhOh.new(id: 1)
        end.to raise_error(ArgumentError,
                           /cannot bind attribute 'id' between UhOh and Mistake. ID is reserved for primary keys in Ruby on Rails/)
      end

      it "binds attributes on change" do
        instance = test_class.new(age: 30, datasource: s3_attrs)
        expect(instance.datasource.root_dir).to eq PROJECT_ROOT.join("spec").to_s

        # Block gets called to append whenver value gets updated!
        expect(instance.datasource.synced_directory.root_dir).to eq PROJECT_ROOT.join("spec").join("secrets").to_s

        puts "Changing value of project root!"
        instance.root_dir = PROJECT_ROOT.to_s
        expect(instance.datasource.root_dir).to eq PROJECT_ROOT.to_s

        # Block gets called to append whenver value gets updated!
        expect(instance.datasource.synced_directory.root_dir).to eq PROJECT_ROOT.join("secrets").to_s
        expect(instance.preprocessor.directory).to eq PROJECT_ROOT.to_s

        instance.datasource.s3_bucket = "different-bucket"
        expect(instance.datasource.synced_directory.s3_bucket).to eq "different-bucket"
      end

      it "passes to intermediate blocks always" do
        instance = test_class.new(age: 30, datasource: Polars::DataFrame.new({ a: [1, 2, 3] }),
                                  complex_chain: "This thang")

        expect(instance.complex_chain).to eq "This thang is cool"
        expect(instance.preprocessor.complex_chain).to eq "This thang is cool and rocks my socks"
        expect(instance.datasource.complex_chain).to eq "This thang is cool and super cool"

        instance.complex_chain = "Other thangs"

        expect(instance.complex_chain).to eq "Other thangs is cool"
        expect(instance.preprocessor.complex_chain).to eq "Other thangs is cool and rocks my socks"
        expect(instance.datasource.complex_chain).to eq "Other thangs is cool and super cool"
      end
    end

    describe "Dependencies" do
      it "defines a dependency with a single option" do
        preprocessing_steps = { annual_revenue: { median: true } }
        instance = test_class.new(age: 30, preprocessing_steps: preprocessing_steps, datasource: s3_attrs)

        expect(instance.preprocessor).to be_a(Test::Data::PreprocessingSteps)
        expect(instance.preprocessing_steps).to match(hash_including(preprocessing_steps))
      end

      it "passes configuration to the single-option dependency in a hash-style" do
        class SomethingNew
          include GlueGun::DSL

          dependency :hash_style_dep do |dependency|
            dependency.set_class OpenStruct
            dependency.bind_attribute :a
            dependency.bind_attribute :b
            dependency.bind_attribute :c
          end
        end

        instance = SomethingNew.new(hash_style_dep: { a: 1, b: 2, c: 3 })
        expect(instance.hash_style_dep).to be_a(OpenStruct)
        expect(instance.hash_style_dep.a).to eq 1
        expect(instance.hash_style_dep.b).to eq 2
        expect(instance.hash_style_dep.c).to eq 3

        instance = SomethingNew.new(hash_style_dep: { a: 1 })
        expect(instance.hash_style_dep.a).to eq 1
      end

      it "creates a dependency with multiple options" do
        instance = test_class.new(age: 30, datasource: s3_attrs)
        expect(instance.datasource).to be_a(Test::Data::Datasource::S3Datasource)
        expect(instance.datasource.synced_directory.s3_bucket).to eq("my-bucket")
      end

      it "uses the default option when no specific option is provided" do
        instance = test_class.new(age: 30)
        expect(instance.datasource).to be_a(NoOp)
      end

      it "is valid when deps invalid, but will validate dependencies when asked" do
        inst = test_class.new(age: 30, datasource: { s3: { s3_bucket: nil } })
        expect(inst).to be_valid
        expect(inst.validate_dependencies).to be(false)
        expect(inst.errors.to_hash).to eq({
                                            "datasource.s3_bucket": ["can't be blank"],
                                            "datasource.s3_secret_access_key": ["can't be blank"]
                                          })
      end

      it "uses the when block to determine the correct option when using when block" do
        df = Polars::DataFrame.new({ id: [1, 2, 3] })
        instance = test_class.new(age: 30, datasource: df)

        expect(instance.datasource).to be_a(Test::Data::Datasource::PolarsDatasource)
        expect(instance.datasource.df).to eq df
      end

      it "can reference other dependencies in when block" do
        df = Polars::DataFrame.new({ id: [1, 2, 3] })
        instance = test_class.new(age: 30, datasource: df)

        expect(instance.datasource_helper).to be_a(PolarsHelper)
      end

      it "respects dependency-injection" do
        df = Polars::DataFrame.new({ a: [1] })
        source = Test::Data::Datasource::PolarsDatasource.new(df: df)
        instance = test_class.new(age: 30, datasource: source)
        expect(instance.datasource).to be source
        expect(instance.datasource.df).to be df
      end
    end

    describe "Inheritance" do
      it "inherits attributes and dependencies from the parent class" do
        inst = SomethingCool.new(age: 30)
        expect(inst.id).to eq "Default Name"

        instance = child_class.new(age: 30)
        expect(instance.id).to eq("Default Name")
        expect(instance.child_attr).to eq("Child Attr")
      end

      it "hardcodes default dependencies" do
        instance = child_class.new(age: 30)
        expect(instance.datasource).to be_a(Test::Data::Datasource::S3Datasource)
        expect(instance.datasource.s3_bucket).to eq("my-bucket")
        expect(instance.datasource.s3_access_key_id).to eq("12345")
      end

      it "allows override of default dependencies" do
        instance = child_class.new(age: 30, datasource: "/path")
        expect(instance.datasource).to be_a(Test::Data::Datasource::FileDatasource)
        expect(instance.datasource.root_dir).to eq("/path")
      end
    end

    describe "Error Handling" do
      it "raises an error when an unknown dependency option is provided" do
        expect do
          test_class.new(age: 30, datasource: { RANDOM: {} })
        end.to raise_error(ArgumentError, /Unknown datasource option/)
      end

      it "raises an error when multiple default options are defined for a dependency" do
        expect do
          Class.new do
            include GlueGun::DSL
            dependency :invalid do |dependency|
              dependency.option :option1 do |option|
                option.default
              end
              dependency.option :option2 do |option|
                option.default
              end
            end
          end
        end.to raise_error(ArgumentError, /Multiple default options found for invalid/)
      end
    end

    describe "When Block" do
      it "uses the when block with a string input for local" do
        instance = test_class.new(age: 30, datasource: "/local/path")
        expect(instance.datasource).to be_a(Test::Data::Datasource::FileDatasource)
        expect(instance.datasource.root_dir).to eq("/local/path")
      end

      it "does not call attribute blocks when when blocks are invoked" do
        instance = test_class.new(age: 30, datasource: { directory: {} })
        expect(instance.datasource).to be_a(Test::Data::Datasource::FileDatasource)

        # When when block NOT invoked, block is called
        expect(instance.datasource.root_dir).to eq(PROJECT_ROOT.join("spec/bingo/bangos").to_s)

        # When when block IS invoked
        instance = test_class.new(age: 30, datasource: "/usr/path")
        expect(instance.datasource.root_dir).to eq "/usr/path"
      end
    end
  end

  # Add a new ActiveRecord-based test class
  describe "ActiveRecord Integration" do
    class ActiveRecordDependency < ActiveRecord::Base
      include GlueGun::DSL
      validates :custom_field, presence: true
      validates :processed_field, presence: true
    end

    class ActiveRecordTest < ActiveRecord::Base
      include GlueGun::DSL

      attribute :root_dir, :string

      validates :custom_field, presence: true

      def processed_field=(value)
        super(value.to_i * 3)
      end

      dependency :ar_dependency do |dependency|
        dependency.set_class ActiveRecordDependency
        dependency.bind_attribute :custom_field
        dependency.bind_attribute :processed_field
      end

      dependency :preprocessor do |dependency|
        dependency.set_class Test::Data::PreprocessingSteps
        dependency.bind_attribute :directory, source: :root_dir
        dependency.bind_attribute :custom_field

        dependency.when do |dep|
          case dep
          when String
            { option: :default, as: :directory }
          end
        end
      end

      dependency :datasource do |dependency|
        dependency.option :no_op do |option|
          option.default
          option.set_class NoOp
        end

        dependency.option :s3 do |option|
          option.set_class Test::Data::Datasource::S3Datasource
          option.bind_attribute :root_dir
          option.bind_attribute :s3_bucket, required: true
          option.bind_attribute :s3_access_key_id, required: true
          option.bind_attribute :polars_args, required: true, default: {}
        end

        dependency.option :directory do |option|
          option.set_class Test::Data::Datasource::FileDatasource
          option.bind_attribute :root_dir do |value|
            File.join(value, "bingo/bangos")
          end
        end

        dependency.option :polars do |option|
          option.set_class Test::Data::Datasource::PolarsDatasource
          option.bind_attribute :complex_chain do |value|
            "#{value} and super cool"
          end
        end

        dependency.when do |dep|
          case dep
          when Polars::DataFrame
            { option: :polars, as: :df }
          when String
            { option: :directory, as: :root_dir }
          end
        end
      end
    end

    let(:ar_instance) { ActiveRecordTest.new(custom_field: "test_value") }

    it "defines attributes on an ActiveRecord model" do
      expect(ar_instance.custom_field).to eq "test_value"
      expect(ar_instance.root_dir).to eq File.join(PROJECT_ROOT, "spec")
    end

    it "processes attributes with a block" do
      ar_instance.processed_field = "5"
      expect(ar_instance.processed_field).to eq 15
    end

    it "validates attributes" do
      invalid_instance = ActiveRecordTest.new
      expect(invalid_instance.valid?).to be false
      expect(invalid_instance.errors[:custom_field]).to include("can't be blank")
    end

    describe "Attribute binding" do
      it "binds attributes with all ActiveRecord methods" do
        ar_instance.custom_field = "1"
        expect(ar_instance.ar_dependency.custom_field).to eq "1"

        ar_instance.assign_attributes(custom_field: "2")
        expect(ar_instance.ar_dependency.custom_field).to eq "2"

        ar_instance.update!(custom_field: "3")
        expect(ar_instance.ar_dependency.custom_field).to eq "3"
      end

      it "does not bind unbound attributes" do
        ar_instance.custom_field = "sweet stuff!"
        ar_instance.unbound_field = 1

        expect(ar_instance.ar_dependency.custom_field).to eq "sweet stuff!"
        expect(ar_instance.ar_dependency.unbound_field).to be_nil
      end

      it "propagates bound attributes when initialized post-hoc" do
        ar_instance.preprocessor = { custom_field: "burger king" }
        expect(ar_instance.preprocessor.custom_field).to eq "burger king" # Override
        expect(ar_instance.preprocessor.directory).to eq ar_instance.root_dir # Propagate
        expect(ar_instance.preprocessor.directory).to eq File.join(PROJECT_ROOT, "spec")

        ar_instance.root_dir = "/etc"
        expect(ar_instance.preprocessor.directory).to eq "/etc"
      end

      it "propagates bound attributes when dependency-injected post-hoc" do
        ar_instance.preprocessor = Test::Data::PreprocessingSteps.new({ custom_field: "burger king" })
        expect(ar_instance.preprocessor.custom_field).to eq "burger king"
        expect(ar_instance.preprocessor.directory).to be_nil # DOES NOT PROPAGATE

        ar_instance.root_dir = "/etc" # But now will
        expect(ar_instance.preprocessor.directory).to eq "/etc"
      end
    end

    it "uses the when block for dependency options" do
      ar_instance.preprocessor = "dependency_path"
      expect(ar_instance.preprocessor).to be_a(Test::Data::PreprocessingSteps)
      expect(ar_instance.preprocessor.directory).to eq "dependency_path"
      expect(ar_instance.preprocessor.custom_field).to eq "test_value"
    end

    it "defines dependencies with options" do
      ar_instance.datasource = { s3: { s3_bucket: "my-bucket" } }
      expect(ar_instance.datasource).to be_a(Test::Data::Datasource::S3Datasource)
      expect(ar_instance.datasource).to_not be_valid
      expect(ar_instance.datasource.errors.to_hash).to eq({
                                                            s3_access_key_id: ["can't be blank"],
                                                            s3_secret_access_key: ["can't be blank"]
                                                          })
    end

    it "validates dependencies when validating parent" do
      expect(ar_instance).to be_valid
      expect(ar_instance.validate_dependencies).to be(false)
      expect(ar_instance.errors.to_hash).to eq({
                                                 "ar_dependency.processed_field": ["can't be blank"]
                                               })
      ar_instance.processed_field = 1
      expect(ar_instance).to be_valid
      expect(ar_instance.validate_dependencies).to be true
      ar_instance.save
      inst = ActiveRecordTest.find(ar_instance.id)
      expect(ar_instance.processed_field).to eq inst.processed_field
      ar_instance.datasource = { s3: { s3_bucket: "my-bucket" } }
      expect(ar_instance.datasource).to_not be_valid
      expect(ar_instance.validate_dependencies).to be(false)
      expect(ar_instance.errors.to_hash).to eq({
                                                 "datasource.s3_access_key_id": ["can't be blank"],
                                                 "datasource.s3_secret_access_key": ["can't be blank"]
                                               })
      ar_instance.datasource.s3_access_key_id = "123"
      ar_instance.datasource.s3_secret_access_key = "123"
      expect(ar_instance.validate_dependencies).to be true
    end

    it "raises an error for unknown attributes" do
      expect { ar_instance.unknown_attribute = "value" }.to raise_error(NoMethodError)
    end
  end

  describe "Factories" do
    let(:s3_attrs) do
      {
        s3: {
          s3_bucket: "my-bucket",
          s3_access_key_id: "12345",
          s3_secret_access_key: "67890"
        }
      }
    end
    # Define a new class that uses the DatasourceFactory
    class Dataset
      include GlueGun::DSL

      dependency :datasource, DatasourceFactory
    end

    class DatasetWithDefault
      include GlueGun::DSL

      dependency :datasource, FactoryWithDefault
    end

    it "creates a datasource using the factory" do
      instance = Dataset.new(datasource: s3_attrs)
      expect(instance.datasource).to be_a(Test::Data::Datasource::S3Datasource)
      expect(instance.datasource.s3_bucket).to eq("my-bucket")
    end

    it "uses the default option when no specific option is provided" do
      instance = DatasetWithDefault.new
      expect(instance.datasource).to be_a(NoOp)
    end

    it "lazy initializes when no option provided" do
      instance = Dataset.new
      expect(instance.datasource).to be_nil

      instance.datasource = Polars::DataFrame.new({ id: [1, 2, 3] })
      expect(instance.datasource).to be_a Test::Data::Datasource::PolarsDatasource
    end

    it "handles Polars::DataFrame correctly" do
      df = Polars::DataFrame.new({ id: [1, 2, 3] })
      instance = Dataset.new(datasource: df)
      expect(instance.datasource).to be_a(Test::Data::Datasource::PolarsDatasource)
      expect(instance.datasource.df).to eq df
    end

    it "handles string input for directory" do
      instance = Dataset.new(datasource: "/local/path")
      expect(instance.datasource).to be_a(Test::Data::Datasource::FileDatasource)
      expect(instance.datasource.root_dir).to eq("/local/path")
    end

    it "binds attributes from parent to child via factory" do
      class ParentWithFactory
        include GlueGun::DSL
        attribute :root_dir, :string, default: "/default/path"
        dependency :child, DatasourceFactory
      end

      instance = ParentWithFactory.new(child: { s3: { s3_bucket: "test-bucket" } })
      expect(instance.child).to be_a(Test::Data::Datasource::S3Datasource)
      expect(instance.child.root_dir).to eq("/default/path")
      expect(instance.child.s3_bucket).to eq("test-bucket")

      instance = ParentWithFactory.new(root_dir: "/custom/path", child: { s3: { s3_bucket: "test-bucket" } })
      expect(instance.child.root_dir).to eq("/custom/path")
    end
  end

  describe "Factory classes" do
    it "creates a datasource instance when used standalone" do
      df = Polars::DataFrame.new({ id: [1, 2, 3] })
      factory = DatasourceFactory.new(datasource: df)
      expect(factory.datasource).to be_a(Test::Data::Datasource::PolarsDatasource)
      expect(factory.datasource.df).to eq df
    end
  end

  describe "Array of Dependencies" do
    class DatasetWithArrayDependencies
      include GlueGun::DSL

      attribute :root_dir, :string

      dependency :datasources, DatasourceFactory
    end

    it "initializes an array of dependencies" do
      df1 = Polars::DataFrame.new({ id: [1, 2, 3] })
      instance = DatasetWithArrayDependencies.new(datasources: [df1, { s3: { s3_bucket: "xyz" } }])

      expect(instance.datasources.size).to eq(2)
      expect(instance.datasources[0]).to be_a(Test::Data::Datasource::PolarsDatasource)
      expect(instance.datasources[0].df).to eq(df1)
      expect(instance.datasources[1]).to be_a(Test::Data::Datasource::S3Datasource)
      expect(instance.datasources[1].s3_bucket).to eq("xyz")
    end

    it "binds attributes to all dependencies in array" do
      instance = DatasetWithArrayDependencies.new(datasources: [
                                                    { s3: { s3_bucket: "abc" } },
                                                    { s3: { s3_bucket: "xyz" } }
                                                  ])

      expect(instance.datasources.first.root_dir).to eq instance.root_dir
      expect(instance.datasources.last.root_dir).to eq instance.root_dir

      instance.root_dir = PROJECT_ROOT
      expect(instance.datasources.first.root_dir).to eq PROJECT_ROOT.to_s
      expect(instance.datasources.last.root_dir).to eq PROJECT_ROOT.to_s

      instance.root_dir = "/Users/me"
      expect(instance.datasources.first.root_dir).to eq "/Users/me"
      expect(instance.datasources.last.root_dir).to eq "/Users/me"
    end

    it "handles mixed types in the array" do
      df = Polars::DataFrame.new({ id: [1, 2, 3] })
      instance = DatasetWithArrayDependencies.new(datasources: [{ s3: { s3_bucket: "abc" } }, df])

      expect(instance.datasources.size).to eq(2)
      expect(instance.datasources[0]).to be_a(Test::Data::Datasource::S3Datasource)
      expect(instance.datasources[0].s3_bucket).to eq("abc")
      expect(instance.datasources[1]).to be_a(Test::Data::Datasource::PolarsDatasource)
      expect(instance.datasources[1].df).to eq(df)
    end
  end

  describe "Hash of Dependencies" do
    class DatasetWithHashDependencies
      include GlueGun::DSL

      attribute :root_dir, :string

      dependency :datasources, DatasourceFactory
    end

    it "initializes a hash of dependencies" do
      df1 = Polars::DataFrame.new({ id: [1, 2, 3] })
      instance = DatasetWithHashDependencies.new(datasources: {
                                                   source1: df1,
                                                   source2: { s3: { s3_bucket: "xyz" } }
                                                 })

      expect(instance.datasources.size).to eq(2)
      expect(instance.datasources[:source1]).to be_a(Test::Data::Datasource::PolarsDatasource)
      expect(instance.datasources[:source1].df).to eq(df1)
      expect(instance.datasources[:source2]).to be_a(Test::Data::Datasource::S3Datasource)
      expect(instance.datasources[:source2].s3_bucket).to eq("xyz")
    end

    it "binds attributes to all dependencies in hash" do
      instance = DatasetWithHashDependencies.new(datasources: {
                                                   source1: { s3: { s3_bucket: "abc" } },
                                                   source2: { s3: { s3_bucket: "xyz" } }
                                                 })

      expect(instance.datasources[:source1].root_dir).to eq instance.root_dir
      expect(instance.datasources[:source2].root_dir).to eq instance.root_dir

      instance.root_dir = PROJECT_ROOT
      expect(instance.datasources[:source1].root_dir).to eq PROJECT_ROOT.to_s
      expect(instance.datasources[:source2].root_dir).to eq PROJECT_ROOT.to_s

      instance.root_dir = "/Users/me"
      expect(instance.datasources[:source1].root_dir).to eq "/Users/me"
      expect(instance.datasources[:source2].root_dir).to eq "/Users/me"
    end

    it "handles mixed types in the hash" do
      df = Polars::DataFrame.new({ id: [1, 2, 3] })
      instance = DatasetWithHashDependencies.new(datasources: {
                                                   source1: { s3: { s3_bucket: "abc" } },
                                                   source2: df
                                                 })

      expect(instance.datasources.size).to eq(2)
      expect(instance.datasources[:source1]).to be_a(Test::Data::Datasource::S3Datasource)
      expect(instance.datasources[:source1].s3_bucket).to eq("abc")
      expect(instance.datasources[:source2]).to be_a(Test::Data::Datasource::PolarsDatasource)
      expect(instance.datasources[:source2].df).to eq(df)
    end

    it "allows accessing dependencies by key" do
      instance = DatasetWithHashDependencies.new(datasources: {
                                                   source1: { s3: { s3_bucket: "abc" } },
                                                   source2: "/path/to/dir"
                                                 })

      expect(instance.datasources[:source1]).to be_a(Test::Data::Datasource::S3Datasource)
      expect(instance.datasources[:source2]).to be_a(Test::Data::Datasource::FileDatasource)
      expect(instance.datasources[:source1].s3_bucket).to eq("abc")
      expect(instance.datasources[:source2].root_dir).to eq("/path/to/dir")
    end
  end

  describe "Flexible dependencies" do
    class FlexibleDataset
      include GlueGun::DSL

      attribute :root_dir, :string
      dependency :datasource, DatasourceFactory
    end

    let(:s3_attrs) do
      { s3: { s3_bucket: "my-bucket", s3_secret_access_key: "secret" } }
    end

    describe "Standalone dependency" do
      it "handles a single dependency" do
        instance = FlexibleDataset.new(datasource: s3_attrs)
        expect(instance.datasource).to be_a(Test::Data::Datasource::S3Datasource)
        expect(instance.datasource.s3_bucket).to eq("my-bucket")
      end

      it "handles dependency injection" do
        df = Polars::DataFrame.new({ id: [1, 2, 3] })
        instance = FlexibleDataset.new(datasource: df)
        expect(instance.datasource).to be_a(Test::Data::Datasource::PolarsDatasource)
        expect(instance.datasource.df).to eq(df)
      end

      it "is nil if no option provided" do
        instance = FlexibleDataset.new
        expect(instance.datasource).to be_nil
      end
    end

    describe "Array of dependencies" do
      it "handles empty array" do
        instance = FlexibleDataset.new(datasource: [])
        expect(instance.datasource.count).to eq 0
      end

      it "handles an array of dependencies" do
        df = Polars::DataFrame.new({ id: [1, 2, 3] })
        instance = FlexibleDataset.new(datasource: [s3_attrs, df, "/local/path"])

        expect(instance.datasource).to be_an(Array)
        expect(instance.datasource.size).to eq(3)
        expect(instance.datasource[0]).to be_a(Test::Data::Datasource::S3Datasource)
        expect(instance.datasource[1]).to be_a(Test::Data::Datasource::PolarsDatasource)
        expect(instance.datasource[2]).to be_a(Test::Data::Datasource::FileDatasource)
      end
    end

    describe "Hash of dependencies" do
      it "handles a hash of dependencies" do
        df = Polars::DataFrame.new({ id: [1, 2, 3] })
        instance = FlexibleDataset.new(datasource: {
                                         source1: s3_attrs,
                                         source2: df,
                                         source3: "/local/path"
                                       })

        expect(instance.datasource).to be_a(Hash)
        expect(instance.datasource.size).to eq(3)
        expect(instance.datasource[:source1]).to be_a(Test::Data::Datasource::S3Datasource)
        expect(instance.datasource[:source2]).to be_a(Test::Data::Datasource::PolarsDatasource)
        expect(instance.datasource[:source3]).to be_a(Test::Data::Datasource::FileDatasource)
      end
    end

    describe "Mixed types and edge cases" do
      it "handles nested hashes correctly" do
        instance = FlexibleDataset.new(datasource: {
                                         source1: { s3: { s3_bucket: "bucket1" } },
                                         source2: { s3: { s3_bucket: "bucket2" } }
                                       })

        expect(instance.datasource).to be_a(Hash)
        expect(instance.datasource.size).to eq(2)
        expect(instance.datasource[:source1]).to be_a(Test::Data::Datasource::S3Datasource)
        expect(instance.datasource[:source2]).to be_a(Test::Data::Datasource::S3Datasource)
        expect(instance.datasource[:source1].s3_bucket).to eq("bucket1")
        expect(instance.datasource[:source2].s3_bucket).to eq("bucket2")
      end

      it "raises an error for invalid types" do
        expect do
          FlexibleDataset.new(datasource: { invalid_type: { some: "config" } })
        end.to raise_error(ArgumentError, /Unknown datasource option/)
      end
    end
  end
end
