require "test_helper"

class IssueContextHelperTest < ActionView::TestCase
  test "flatten_context joins nested keys and keeps empty hashes as values" do
    flat = flatten_context({ "runtime" => { "ruby" => "3.4.1", "rails" => { "version" => "8.1" } }, "env" => {}, "host" => "web-1" })

    assert_equal({ "runtime.ruby" => "3.4.1", "runtime.rails.version" => "8.1", "env" => {}, "host" => "web-1" }, flat)
  end

  test "affected user name falls back from name to username to the email's local part" do
    assert_equal "Mara", affected_user_name({ "name" => "Mara", "username" => "mk" })
    assert_equal "mk", affected_user_name({ "username" => "mk", "email" => "m@x.io" })
    assert_equal "m", affected_user_name({ "email" => "m@x.io" })
    assert_equal "Anonymous user", affected_user_name({})
  end

  test "affected user identity never shows the email domain" do
    assert_equal "id 5521 · mara@…", affected_user_identity({ "id" => 5521, "email" => "mara@example.com" })
  end
end
