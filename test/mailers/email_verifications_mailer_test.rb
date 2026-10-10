require "test_helper"

class EmailVerificationsMailerTest < ActionMailer::TestCase
  setup { @user = users(:jo) }

  test "verify links to a token that confirms the address" do
    mail = EmailVerificationsMailer.verify(@user)

    assert_equal "Confirm your email address", mail.subject
    assert_equal [ @user.email_address ], mail.to
    token = mail.text_part.body.to_s[%r{http://example\.com/email_verification\?token=(\S+)}, 1]
    assert_equal @user, User.find_by_email_verification_token(CGI.unescape(token))
  end

  test "has an HTML part built from the shared layout and a plain-text part" do
    mail = EmailVerificationsMailer.verify(@user)
    html = mail.html_part.body.to_s

    assert_includes html, "Confirm email address"
    assert_includes html, "Good Sorcery"
    assert_includes html, "Confirm #{@user.email_address} to finish setting up", "preheader"
    assert_includes html, "used to sign up for Good Sorcery", "template footer"
    assert_includes mail.text_part.body.to_s, "expires in 3 days"
  end

  test "the link doesn't reveal the email address" do
    token = CGI.unescape(EmailVerificationsMailer.verify(@user).text_part.body.to_s[/token=(\S+)/, 1])
    payload = Base64.decode64(token.split("--").first.tr("-_", "+/"))

    assert_includes payload, "_rails", "decoded the signed message"

    assert_not_includes payload, @user.email_address
  end

  test "the plain-text part isn't HTML-escaped" do
    @user.update_column(:name, "D'Arcy Jones")
    text = EmailVerificationsMailer.verify(@user).text_part.body.to_s

    assert_includes text, "Hi D'Arcy, thanks"
    assert_includes text, "You're receiving this email"
    assert_not_includes text, "&#39;"
  end

  test "escapes the user's name" do
    @user.update_column(:name, "<b>Jo</b>")
    html = EmailVerificationsMailer.verify(@user).html_part.body.to_s

    assert_includes html, "&lt;b&gt;Jo&lt;/b&gt;"
    assert_not_includes html, "<b>Jo</b>"
  end
end
