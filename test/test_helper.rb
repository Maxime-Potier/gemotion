ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

test_database = ActiveRecord::Base.connection_db_config.database.to_s
unless test_database.end_with?("_test")
  raise <<~MESSAGE
    Refusing to run tests against #{test_database.inspect}.
    Configure TEST_DATABASE_URL to point to a dedicated database ending in _test.
  MESSAGE
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Add more helper methods to be used by all tests here...
  end
end
