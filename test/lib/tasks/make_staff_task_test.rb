require "test_helper"
require "rake"

class MakeStaffTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("goodsorcery:make_staff")
  end

  teardown { ENV.delete("EMAIL") }

  test "makes the user with that email address staff" do
    ENV["EMAIL"] = " Philip@Example.com "

    assert_output("philip@example.com is now staff.\n") { run_task }
    assert users(:philip).reload.staff?
  end

  test "fails without EMAIL" do
    _, stderr = capture_io { assert_exits_with_failure { run_task } }
    assert_includes stderr, "Usage: bin/rails goodsorcery:make_staff EMAIL="
  end

  test "fails when no user has the email address" do
    ENV["EMAIL"] = "nobody@example.com"

    _, stderr = capture_io { assert_exits_with_failure { run_task } }
    assert_includes stderr, "No user has the email address nobody@example.com."
  end

  private
    def run_task
      Rake::Task["goodsorcery:make_staff"].execute
    end

    def assert_exits_with_failure(&)
      error = assert_raises(SystemExit, &)
      assert_not error.success?
    end
end
