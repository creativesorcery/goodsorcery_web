require "test_helper"

class EnvironmentToneTest < ActiveSupport::TestCase
  test "production-like names are coral" do
    %w[production prod live Production PROD Live].each do |name|
      assert_equal :coral, EnvironmentTone.of(name), name
      assert EnvironmentTone.production?(name), name
    end
  end

  test "staging-like names are lilac" do
    %w[staging stage preview qa uat Staging QA].each do |name|
      assert_equal :lilac, EnvironmentTone.of(name), name
      assert_not EnvironmentTone.production?(name), name
    end
  end

  test "local and test names are muted" do
    %w[development dev test local Development].each { |name| assert_equal :muted, EnvironmentTone.of(name), name }
  end

  test "anything else is iris" do
    [ "eu-west", "production-eu", "canary", "", nil ].each { |name| assert_equal :iris, EnvironmentTone.of(name), name.inspect }
  end
end
