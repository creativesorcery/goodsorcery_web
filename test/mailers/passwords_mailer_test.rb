require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset" do
    user = users(:philip)
    mail = PasswordsMailer.reset(user)

    assert_equal "Reset your password", mail.subject
    assert_equal [ user.email_address ], mail.to
    assert_match "http://example.com/password/edit?token=", mail.body.encoded
    assert_no_match %r{/passwords?/[^/\s?]+/edit}, mail.body.encoded, "the token is not a path segment"
  end

  test "sender defaults to no-reply at the link host" do
    assert_equal [ "no-reply@example.com" ], PasswordsMailer.reset(users(:philip)).from
  end
end
