require "pry"
require "spec_helper"

PROJECT_ROOT = Pathname.new(File.expand_path("..", __dir__))

RSpec.describe GlueGun::DSL do
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

          validates :s3_bucket, :s3_access_key_id, :s3_secret_access_key, presence: true

          dependency :synced_directory do |dep|
            dep.set_class Test::Data::SyncedDir
            dep.attribute :root_dir
            dep.attribute :s3_bucket
          end
        end

        class FileDatasource
          include ActiveModel::Model
          include ActiveModel::Attributes
          attribute :root_dir, :string

          validates :root_dir, presence: true
        end

        class PolarsDatasource
          include ActiveModel::Model
          include ActiveModel::Attributes
          attribute :df

          validates :df, presence: true
        end
      end
    end
  end

  # Define SomethingCool class using the new GlueGun::DSL
  class SomethingCool
    include GlueGun::DSL

    attribute :id, :string, default: "Default Name"
    attribute :age, :integer
    validates :age, presence: true
    attribute :root_dir, :string

    attribute :processed_attr, :integer, default: 0

    def processed_attr=(value)
      super(value.to_i * 2)
    end

    attribute :preprocessing_steps, :hash, default: {}

    dependency :preprocessor do |dependency|
      dependency.set_class Test::Data::PreprocessingSteps
      dependency.attribute :directory, source: :root_dir
    end

    dependency :datasource do |dependency|
      dependency.option :no_op do |option|
        option.default
        option.set_class NoOp
      end

      dependency.option :s3 do |option|
        option.set_class Test::Data::Datasource::S3Datasource
        option.attribute :root_dir
        option.attribute :s3_bucket, required: true, default: "default-bucket"
      end

      dependency.option :directory do |option|
        option.set_class Test::Data::Datasource::FileDatasource
      end

      dependency.option :polars do |option|
        option.set_class Test::Data::Datasource::PolarsDatasource
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
      instance = test_class.new(age: 30, datasource: { s3: { s3_access_key_id: "123", s3_secret_access_key: "456" } })
      expect(instance.datasource.s3_bucket).to eq "default-bucket"
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
      expect(b.fruits).to eq "pear"
      expect { Picklist.new(fruits: "raspberry") }.to raise_error(ActiveModel::ValidationError)
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
      expect(a.valid?).to be true
      b = ConditionalPicklist.new(task: "classification", metrics: "accuracy")
      expect(b.valid?).to be true
      expect do
        ConditionalPicklist.new(task: "regression",
                                metrics: "accuracy")
      end.to raise_error(ActiveModel::ValidationError, /accuracy is not an allowed metric for task regression/)
    end

    it "raises an error when a required attribute is not provided" do
      expect { test_class.new(datasource: s3_attrs) }.to raise_error(ActiveModel::ValidationError, /Age can't be blank/)
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
        dependency :dep do |dependency|
          dependency.set_class ExampleDep
          dependency.attribute :valid
        end
      end

      example = Example.new(dep: { valid: true })
      expect(example.dep.valid).to eq true

      expect do
        Example.new(dep: { invalid: true })
      end.to raise_error(ArgumentError, /ExampleDep does not respond to invalid/)
    end
  end

  describe "When attribute changes" do
    it "binds attributes on change" do
      instance = test_class.new(age: 30, datasource: s3_attrs)
      expect(instance.datasource.root_dir).to eq PROJECT_ROOT.join("spec").to_s

      instance.root_dir = PROJECT_ROOT.to_s
      expect(instance.datasource.root_dir).to eq PROJECT_ROOT.to_s
      expect(instance.datasource.synced_directory.root_dir).to eq PROJECT_ROOT.to_s
      expect(instance.preprocessor.directory).to eq PROJECT_ROOT.to_s

      instance.datasource.s3_bucket = "different-bucket"
      expect(instance.datasource.synced_directory.s3_bucket).to eq "different-bucket"
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
          dependency.attribute :a
          dependency.attribute :b
          dependency.attribute :c
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

    it "uses the when block with a string input for local" do
      instance = test_class.new(age: 30, datasource: "/local/path")
      expect(instance.datasource).to be_a(Test::Data::Datasource::FileDatasource)
      expect(instance.datasource.root_dir).to eq("/local/path")
    end

    it "uses the default option when no specific option is provided" do
      instance = test_class.new(age: 30)
      expect(instance.datasource).to be_a(NoOp)
    end

    it "raises an error when a required attribute for a dependency is not provided" do
      expect do
        test_class.new(age: 30, datasource: { s3: { s3_bucket: nil } })
      end.to raise_error(ArgumentError, /Missing required attribute 's3_bucket'/)
    end

    it "uses the when block to determine the correct option when using when block" do
      df = Polars::DataFrame.new({ id: [1, 2, 3] })
      instance = test_class.new(age: 30, datasource: df)

      expect(instance.datasource).to be_a(Test::Data::Datasource::PolarsDatasource)
      expect(instance.datasource.df).to eq df
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
end
