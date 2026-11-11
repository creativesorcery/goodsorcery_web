require "test_helper"
require "rake"

class CreateOwnerTaskTest < ActiveSupport::TestCase
  KEYS = %w[EMAIL NAME ACCOUNT PASSWORD STAFF].freeze

  # Start from a clean slate too: a shell may already export NAME or EMAIL.
  setup do
    @saved = ENV.to_h.slice(*KEYS)
    KEYS.each { ENV.delete(it) }
    Rails.application.load_tasks unless Rake::Task.task_defined?("goodsorcery:create_owner")
  end

  teardown do
    KEYS.each { ENV.delete(it) }
    ENV.update(@saved)
  end

  test "creates the owner from EMAIL, NAME, ACCOUNT and PASSWORD" do
    ENV.update("EMAIL" => "owner@example.com", "NAME" => "Alex Rivera", "ACCOUNT" => "Initech", "PASSWORD" => "tps-reports-1")

    assert_output("Created owner@example.com, owner of Initech.\n") { run_task }
    assert User.find_by!(email_address: "owner@example.com").memberships.sole.owner?
  end

  test "fails with the usage when values are missing" do
    _, stderr = capture_io { assert_exits_with_failure { run_task } }
    assert_includes stderr, "Usage: bin/rails goodsorcery:create_owner EMAIL="
  end

  test "fails when the email address is taken" do
    ENV.update("EMAIL" => "alex@example.com", "NAME" => "Alex Rivera", "ACCOUNT" => "Initech", "PASSWORD" => "tps-reports-1")

    _, stderr = capture_io { assert_exits_with_failure { run_task } }
    assert_includes stderr, "Email address has already been taken"
  end

  private
    def run_task
      Rake::Task["goodsorcery:create_owner"].execute
    end

    def assert_exits_with_failure(&)
      error = assert_raises(SystemExit, &)
      assert_not error.success?
    end
end
