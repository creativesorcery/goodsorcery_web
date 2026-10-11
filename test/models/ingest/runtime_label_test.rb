require "test_helper"

class Ingest::RuntimeLabelTest < ActiveSupport::TestCase
  test "labels rails and ruby by major.minor" do
    assert_equal "Rails 8.0 · Ruby 3.4", Ingest::RuntimeLabel.new({ "rails" => "8.0.1", "ruby" => "3.4.1 (YJIT on)" }).to_s
    assert_equal "Ruby 3.4", Ingest::RuntimeLabel.new({ "ruby" => "3.4.1" }).to_s
  end

  test "is nil without usable versions" do
    assert_nil Ingest::RuntimeLabel.new({ "ruby" => "head" }).to_s
    assert_nil Ingest::RuntimeLabel.new(nil).to_s
  end
end
