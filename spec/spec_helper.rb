# frozen_string_literal: true

require "bundler"
require "combustion"

Bundler.require :default, :development

Combustion.initialize! :active_record # unless defined?(Combustion::Application)

require "glue_gun"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :active_record_tests do |t|
    t.string :custom_field
    t.integer :processed_field
    t.timestamps
  end

  create_table :active_record_dependencies do |t|
    t.string :custom_field
    t.integer :processed_field
    t.timestamps
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.filter_run_when_matching :focus
end
