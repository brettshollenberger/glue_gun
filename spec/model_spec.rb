require "polars"
require "spec_helper"

module ModelTest
  class PolarsDatasource
    include GlueGun::DSL

    attribute :df

    def data
      df
    end

    def self.serialize(datasource)
      {
        df: JSON.parse(datasource.df.write_json)
      }
    end

    def self.deserialize(options)
      df = options[:df]
      columns = df[:columns].map do |col|
        # Determine the correct data type
        dtype = case col[:datatype]
                when Hash
                  if col[:datatype][:Datetime]
                    Polars::Datetime.new(col[:datatype][:Datetime][0].downcase.to_sym).class
                  else
                    Polars::Utf8
                  end
                else
                  Polars.const_get(col[:datatype])
                end
        # Create a Series for each column
        Polars::Series.new(col[:name], col[:values], dtype: dtype)
      end

      # Create the DataFrame
      options[:df] = Polars::DataFrame.new(columns)
      options
    end
  end

  class S3Datasource
    include GlueGun::DSL

    attribute :verbose, default: false
    attribute :s3_bucket, :string
    attribute :s3_prefix, :string
    attribute :root_dir, :string
    attribute :polars_args, :hash, default: {}

    def polars_args=(args)
      args[:dtypes] = args[:dtypes].stringify_keys if args.key?(:dtypes)
      super(args)
    end

    def s3_prefix=(arg)
      super(arg.to_s.gsub(%r{^/|/$}, ""))
    end

    attribute :s3_access_key_id, :string
    attribute :s3_secret_access_key, :string
    attribute :cache_for

    def data
      files = Dir.glob(File.join(root_dir, "**/*.csv"))
      dfs = files.map do |file|
        Polars.read_csv(file, **polars_args)
      end
      Polars.concat(dfs)
    end

    def serialize
      attributes
    end
  end

  class Datasource < ActiveRecord::Base
    include GlueGun::Model

    service :polars, PolarsDatasource
    service :s3, S3Datasource

    delegate :data, :df, to: :datasource_service
  end

  class DateSplitter
    include GlueGun::DSL

    attribute :today, :datetime
    attribute :date_col, :string
    attribute :months_test, :integer, default: 2
    attribute :months_valid, :integer, default: 2

    def split(df)
      unless df[date_col].dtype.is_a?(Polars::Datetime)
        raise "Date splitter cannot split on non-date col #{date_col}, dtype is #{df[date_col].dtype}"
      end

      validation_date_start, test_date_start = splits

      test_df = df.filter(Polars.col(date_col) >= test_date_start)
      remaining_df = df.filter(Polars.col(date_col) < test_date_start)
      valid_df = remaining_df.filter(Polars.col(date_col) >= validation_date_start)
      train_df = remaining_df.filter(Polars.col(date_col) < validation_date_start)

      [train_df, valid_df, test_df]
    end

    def months(n)
      ActiveSupport::Duration.months(n)
    end

    def splits
      test_date_start = today.advance(months: -months_test).beginning_of_day
      validation_date_start = today.advance(months: -(months_test + months_valid)).beginning_of_day
      [validation_date_start, test_date_start]
    end
  end

  class Split
    include GlueGun::DSL

    attribute :polars_args, :hash, default: {}
    attribute :max_rows_per_file, :integer, default: 1_000_000
    attribute :batch_size, :integer, default: 10_000
    attribute :verbose, :boolean, default: false

    def schema
      polars_args[:dtypes]
    end

    def cast(df)
      cast_cols = schema.keys & df.columns
      df = df.with_columns(
        cast_cols.map do |column|
          dtype = schema[column]
          df[column].cast(dtype).alias(column)
        end
      )
    end

    # List of file paths, these will be csvs
    def save_schema(files)
      combined_schema = {}

      files.each do |file|
        df = Polars.read_csv(file, **polars_args)

        df.schema.each do |column, dtype|
          combined_schema[column] = if combined_schema.key?(column)
                                      resolve_dtype(combined_schema[column], dtype)
                                    else
                                      dtype
                                    end
        end
      end

      polars_args[:dtypes] = combined_schema
    end

    def resolve_dtype(dtype1, dtype2)
      # Example of simple rules: prioritize Float64 over Int64
      if [dtype1, dtype2].include?(:float64)
        :float64
      elsif [dtype1, dtype2].include?(:int64)
        :int64
      else
        # If both are the same, return any
        dtype1
      end
    end

    def split_features_targets(df, split_ys, target)
      raise ArgumentError, "Target column must be specified when split_ys is true" if split_ys && target.nil?

      if split_ys
        xs = df.drop(target)
        ys = df.select(target)
        [xs, ys]
      else
        df
      end
    end

    protected

    def create_progress_bar(segment, total_rows)
      ProgressBar.create(
        title: "Reading #{segment}",
        total: total_rows,
        format: "%t: |%B| %p%% %e"
      )
    end

    def process_block_with_split_ys(block, result, xs, ys)
      case block.arity
      when 3
        result.nil? ? [xs, ys] : block.call(result, xs, ys)
      when 2
        block.call(xs, ys)
        result
      else
        raise ArgumentError, "Block must accept 2 or 3 arguments when split_ys is true"
      end
    end

    def process_block_without_split_ys(block, result, df)
      case block.arity
      when 2
        result.nil? ? df : block.call(result, df)
      when 1
        block.call(df)
        result
      else
        raise ArgumentError, "Block must accept 1 or 2 arguments when split_ys is false"
      end
    end
  end

  class InMemorySplit < Split
    include GlueGun::DSL

    def initialize(options)
      super
      @data = {}
    end

    def save(segment, df)
      @data[segment] = df
    end

    def read(segment, split_ys: false, target: nil, drop_cols: [], filter: nil)
      df = if segment.to_s == "all"
             Polars.concat(%i[train test valid].map { |segment| @data[segment] })
           else
             @data[segment]
           end
      return nil if df.nil?

      df = df.filter(filter) if filter.present?
      drop_cols &= df.columns
      df = df.drop(drop_cols) unless drop_cols.empty?

      split_features_targets(df, split_ys, target)
    end

    def cleanup
      @data.clear
    end

    def split_at
      @data.keys.empty? ? nil : Time.now
    end
  end

  class DatasetService
    include GlueGun::DSL

    attribute :verbose, :boolean, default: false
    attribute :polars_args, :hash, default: {}
    def polars_args=(args)
      super(args.deep_symbolize_keys.inject({}) do |hash, (k, v)|
        hash.tap do
          hash[k] = v
          hash[k] = v.stringify_keys if k == :dtypes
        end
      end)
    end
    attribute :datasource

    dependency :splitter do |dependency|
      dependency.option :date do |option|
        option.default
        option.set_class DateSplitter
        option.bind_attribute :today, required: true
        option.bind_attribute :date_col, required: true
        option.bind_attribute :months_test, required: true
        option.bind_attribute :months_valid, required: true
      end
    end

    dependency :raw do |dependency|
      dependency.option :default do |option|
        option.default
        option.set_class Split
      end

      dependency.option :memory do |option|
        option.set_class InMemorySplit
      end

      dependency.when do |_dep|
        { option: :memory } if datasource.respond_to?(:df)
      end
    end

    # Here we define the processed dataset (uses the Split class)
    # After we learn the dataset statistics, we fill null values
    # using the learned statistics (e.g. fill annual_revenue with median annual_revenue)
    #
    dependency :processed do |dependency|
      dependency.option :default do |option|
        option.default
        option.set_class Split
      end

      dependency.option :memory do |option|
        option.set_class InMemorySplit
      end

      dependency.when do |_dep|
        { option: :memory } if datasource.respond_to?(:df)
      end
    end
  end

  class Dataset < ActiveRecord::Base
    include GlueGun::Model

    service :dataset, DatasetService
    validates :name, presence: true
    belongs_to :datasource,
               foreign_key: :datasource_id
  end
end

RSpec.describe GlueGun::Model do
  describe "Independent models" do
    describe "Polars Datasource" do
      let(:df) do
        df = Polars::DataFrame.new({
                                     id: [1, 2, 3, 4, 5, 6, 7, 8],
                                     rev: [0, 0, 100, 200, 0, 300, 400, 500],
                                     annual_revenue: [300, 400, 5000, 10_000, 20_000, 30, nil, nil],
                                     points: [1.0, 2.0, 0.1, 0.8, nil, 0.1, 0.4, 0.9],
                                     created_date: %w[2021-01-01 2021-01-01 2022-02-02 2024-01-01 2024-06-15 2024-07-01
                                                      2024-08-01 2024-09-01]
                                   })

        # Convert the 'created_date' column to datetime
        df.with_column(
          Polars.col("created_date").str.strptime(Polars::Datetime, "%Y-%m-%d").alias("created_date")
        )
      end

      it "creates polars datasources" do
        # Save the serialized DataFrame to the database
        datasource = ModelTest::Datasource.create!(
          name: "My Polars Df",
          datasource_type: :polars,
          df: df
        )

        datasource = ModelTest::Datasource.find(datasource.id)
        expect(datasource.data).to eq df
      end

      it "delegates to service classes" do
        datasource = ModelTest::Datasource.create!(
          name: "My Polars Df",
          datasource_type: :polars,
          df: df
        )

        expect(datasource).to_not receive(:method_missing)
        expect(datasource.df).to eq df
      end

      it "reloads object" do
        datasource = ModelTest::Datasource.create!(
          name: "My Polars Df",
          datasource_type: :polars,
          df: df
        )
        datasource.reload
        expect(datasource.df).to eq df
      end
    end

    describe "S3 Datasource" do
      it "saves and loads the s3 datasource" do
        path = SPEC_ROOT.join("files")

        s3_datasource = ModelTest::Datasource.create!(
          name: "s3 Datasource",
          datasource_type: :s3,
          root_dir: path,
          s3_bucket: "bucket",
          s3_prefix: "raw",
          s3_access_key_id: "12345",
          s3_secret_access_key: "12345"
        )

        datasource = ModelTest::Datasource.find(s3_datasource.id)
        expect(datasource.datasource_service.s3_bucket).to eq "bucket"
        expect(datasource.data).to eq(Polars.read_csv(path.join("file.csv")))
      end

      describe "Querying" do
        it "find_or_create_by" do
          path = SPEC_ROOT.join("files")

          s3_datasource = ModelTest::Datasource.find_or_create_by!(
            name: "s3 Datasource",
            datasource_type: :s3,
            root_dir: path.to_s,
            s3_bucket: "bucket",
            s3_prefix: "raw",
            s3_access_key_id: "12345",
            s3_secret_access_key: "12345"
          )

          expect(s3_datasource.name).to eq "s3 Datasource"
          expect(s3_datasource.s3_bucket).to eq "bucket"
          expect(s3_datasource.data).to eq(Polars.read_csv(path.join("file.csv")))

          # This tests the find_by (when it's already created), still initializes the dependency
          s3_datasource = ModelTest::Datasource.find_or_create_by!(
            name: "s3 Datasource",
            datasource_type: :s3,
            root_dir: path.to_s,
            s3_bucket: "bucket",
            s3_prefix: "raw",
            s3_access_key_id: "12345",
            s3_secret_access_key: "12345"
          )
          expect(s3_datasource.data).to eq(Polars.read_csv(path.join("file.csv")))
        end

        it "with block" do
          path = SPEC_ROOT.join("files")

          s3_datasource = ModelTest::Datasource.find_or_create_by(
            name: "s3 Datasource",
            datasource_type: :s3
          ) do |datasource|
            datasource.assign_attributes(
              root_dir: path.to_s,
              s3_bucket: "bucket",
              s3_prefix: "raw",
              s3_access_key_id: "12345",
              s3_secret_access_key: "12345"
            )
          end

          expect(s3_datasource.name).to eq "s3 Datasource"
          expect(s3_datasource.s3_bucket).to eq "bucket"
          expect(s3_datasource.s3_prefix).to eq "raw"
          expect(s3_datasource.datasource_service.s3_prefix).to eq "raw"
          expect(s3_datasource.data).to eq(Polars.read_csv(path.join("file.csv")))
        end
      end
    end
  end

  describe "Models w/ dependencies" do
    let(:df) do
      df = Polars::DataFrame.new({
                                   id: [1, 2, 3, 4, 5, 6, 7, 8],
                                   rev: [0, 0, 100, 200, 0, 300, 400, 500],
                                   annual_revenue: [300, 400, 5000, 10_000, 20_000, 30, nil, nil],
                                   points: [1.0, 2.0, 0.1, 0.8, nil, 0.1, 0.4, 0.9],
                                   created_date: %w[2021-01-01 2021-01-01 2022-02-02 2024-01-01 2024-06-15 2024-07-01
                                                    2024-08-01 2024-09-01]
                                 })

      # Convert the 'created_date' column to datetime
      df.with_column(
        Polars.col("created_date").str.strptime(Polars::Datetime, "%Y-%m-%d").alias("created_date")
      )
    end

    it "builds them properly" do
      datasource = ModelTest::Datasource.create!(
        name: "My Polars Df",
        datasource_type: :polars,
        df: df
      )

      dataset = ModelTest::Dataset.create(
        name: "My Dataset",
        datasource: datasource,
        splitter: {
          date: {
            months_test: 3
          }
        }
      )

      dataset = ModelTest::Dataset.find(dataset.id)

      expect(dataset.datasource.data).to eq df
      expect(dataset.splitter).to be_a ModelTest::DateSplitter
      expect(dataset.splitter.months_test).to eq 3
      expect(dataset.splitter.months_valid).to eq 2
    end

    it "works with foreign keys" do
      datasource = ModelTest::Datasource.create!(
        name: "My Polars Df",
        datasource_type: :polars,
        df: df
      )

      df2 = Polars::DataFrame.new({ a: [1, 2, 3] })
      datasource2 = ModelTest::Datasource.create!(
        name: "My Polars Df",
        datasource_type: :polars,
        df: df2
      )

      dataset = ModelTest::Dataset.create(
        name: "My Dataset",
        datasource_id: datasource.id,
        splitter: {
          date: {
            months_test: 3
          }
        }
      )

      dataset = ModelTest::Dataset.find(dataset.id)

      expect(dataset.datasource).to be_a ModelTest::Datasource
      expect(dataset.datasource.id).to eq datasource.id

      dataset.update(datasource_id: datasource2.id)

      expect(dataset.datasource).to be_a ModelTest::Datasource
      expect(dataset.datasource.id).to eq datasource2.id
      expect(dataset.datasource.df).to eq df2
      expect(dataset.raw).to be_a(ModelTest::InMemorySplit)
      expect(dataset.processed).to be_a(ModelTest::InMemorySplit)
    end

    it "assigns associations" do
      SPEC_ROOT.join("files")

      datasource = ModelTest::Datasource.create!(
        name: "My Polars Df",
        datasource_type: :polars,
        df: df
      )

      dataset = ModelTest::Dataset.find_or_create_by(name: "My Dataset") do |dataset|
        dataset.assign_attributes(
          datasource: datasource,
          splitter: {
            date: {
              months_test: 3
            }
          }
        )
      end

      expect(dataset.datasource).to eq datasource
      expect(dataset.dataset_service.datasource).to eq datasource
      expect(dataset.splitter).to be_a(ModelTest::DateSplitter)
    end

    it "updates associations" do
      SPEC_ROOT.join("files")

      datasource = ModelTest::Datasource.create!(
        name: "My Polars Df",
        datasource_type: :polars,
        df: df
      )

      dataset = ModelTest::Dataset.find_or_create_by(name: "My Dataset") do |dataset|
        dataset.update(
          datasource: datasource,
          splitter: {
            date: {
              months_test: 3
            }
          }
        )
      end

      expect(dataset.datasource).to eq datasource
      expect(dataset.dataset_service.datasource).to eq datasource
      expect(dataset.splitter).to be_a(ModelTest::DateSplitter)

      dataset.reload
      expect(dataset.dataset_service.datasource).to eq datasource
      expect(dataset.splitter).to be_a(ModelTest::DateSplitter)
    end
  end
end
