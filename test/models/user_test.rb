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

  test "users aren't staff unless granted" do
    assert_equal false, User.new.staff?
    assert_equal false, User.create!(name: "New", email_address: "new@example.com", password: "long-enough").reload.staff?
    assert users(:staffer).staff?
    assert_not users(:philip).staff?
  end

  test "update_staff lets a staff member grant and remove another user's staff access" do
    staffer, philip = users(:staffer), users(:philip)

    assert philip.update_staff("1", by: staffer)
    assert philip.reload.staff?

    assert philip.update_staff("0", by: staffer)
    assert_not philip.reload.staff?
  end

  test "update_staff never removes a staff member's own access" do
    staffer = users(:staffer)

    [ "0", false, nil, "" ].each do |value|
      assert_not staffer.update_staff(value, by: staffer), value.inspect
      assert_equal [ User::SELF_DEMOTION ], staffer.errors[:base]
      assert staffer.reload.staff?
      staffer.errors.clear
    end
    assert staffer.update_staff("1", by: staffer), "keeping it is fine"
  end

  test "staff_search matches a name or email substring, case-insensitively, or an exact id" do
    assert_equal [ users(:philip) ], User.staff_search("PHILIP").to_a
    assert_equal [ users(:outsider) ], User.staff_search("umbrella.TEST").to_a
    assert_equal [ users(:jo) ], User.staff_search(users(:jo).id.to_s).to_a
    assert_equal User.count, User.staff_search(" ").count
    assert_empty User.staff_search("nobody-like-this")
  end

  test "staff_search matches LIKE wildcards literally" do
    percent = User.create!(name: "100% Pure", email_address: "pure@example.com", password: "long-enough")
    underscore = User.create!(name: "Snake", email_address: "snake_case@example.com", password: "long-enough")

    assert_equal [ percent ], User.staff_search("%").to_a
    assert_equal [ underscore ], User.staff_search("_").to_a
    assert_equal [ underscore ], User.staff_search("e_c").to_a
  end

  test "staff_search treats digits too long for an id as text" do
    assert_empty User.staff_search("1" * 30)
  end
end
