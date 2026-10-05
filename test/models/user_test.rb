require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires a name and a valid unique email" do
    user = User.new(email_address: "philip@example.com", password: "long-enough")
    assert_not user.valid?
    assert user.errors.added?(:name, :blank)
    assert user.errors.of_kind?(:email_address, :taken)
  end

  test "rejects short passwords" do
    user = User.new(name: "A", email_address: "a@example.com", password: "short")
    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)
  end

  test "falls back to UTC for unknown time zones" do
    assert_equal "UTC", User.new(time_zone: "Mars/Olympus").time_zone
    assert_equal "Europe/Berlin", User.new(time_zone: "Europe/Berlin").time_zone
  end

  test "default account is the earliest membership" do
    user = users(:jo)
    accounts(:umbrella).memberships.create!(user:, role: :member)
    assert_equal accounts(:acme), user.default_account
  end

  test "initials and first name" do
    assert_equal "PN", users(:philip).initials
    assert_equal "Philip", users(:philip).first_name
    assert_equal "C", User.new(name: "cher").initials
  end
end
