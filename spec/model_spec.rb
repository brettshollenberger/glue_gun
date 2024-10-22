require "polars"
require "spec_helper"

module ModelTest
  class PolarsDatasource
    include GlueGun::DSL

    attribute :df

    def data
      df
    end

    def serialize
      {
        df: JSON.parse(df.write_json)
      }
    end

    def deserialize(options)
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

    service do |options|
      if options.key?(:df)
        PolarsDatasource
      elsif options.key?(:s3_bucket)
        S3Datasource
      end
    end

    # delegate_service_methods :data
    delegate :data, to: :datasource_service
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
  end

  class Dataset < ActiveRecord::Base
    include GlueGun::Model

    service DatasetService
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
          df: df
        )

        datasource = ModelTest::Datasource.find(datasource.id)
        expect(datasource.data).to eq df
      end
    end

    describe "S3 Datasource" do
      it "saves and loads the s3 datasource" do
        path = SPEC_ROOT.join("files")

        s3_datasource = ModelTest::Datasource.create!(
          name: "s3 Datasource",
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
    end
  end

  describe "Models w/ dependencies" do
    it "builds them properly" do
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
      datasource = ModelTest::Datasource.create!(
        name: "My Polars Df",
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
  end
end
