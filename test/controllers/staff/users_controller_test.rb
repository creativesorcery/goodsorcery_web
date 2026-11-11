require "test_helper"

class Staff::UsersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:staffer) }

  test "index lists every user, newest first, with a staff badge and no accounts" do
    get staff_users_path

    assert_response :success
    assert_select "#sidebar a.nav-link[aria-current=page][href=?]", staff_users_path
    assert_select "#staff_users tbody tr", User.count
    assert_select "##{dom_id(users(:staffer), :staff)} .chip", text: "Staff"
    assert_select "##{dom_id(users(:alex), :staff)}" do
      assert_select "a[href=?]", staff_user_path(users(:alex)), text: "Alex Rivera"
      assert_select "td", text: "alex@example.com"
      assert_select ".chip", 0
    end
    assert_select "#staff_users", text: /Acme Labs/, count: 0
  end

  test "index searches by name, by email, or by exact id" do
    get staff_users_path(q: "martin")
    assert_select "#staff_users tbody tr", 1
    assert_select "#staff_users", text: /Jo Martin/

    get staff_users_path(q: "@UMBRELLA")
    assert_select "#staff_users tbody tr", 1
    assert_select "#staff_users", text: /outsider@umbrella.test/

    get staff_users_path(q: users(:alex).id)
    assert_select "#staff_users tbody tr", 1
    assert_select "#staff_users", text: /Alex Rivera/
  end

  test "index matches LIKE wildcards literally" do
    get staff_users_path(q: "%")
    assert_select "#staff_users", 0
    assert_select "p", text: "No users match “%”."
  end

  test "index pages through users 25 at a time" do
    26.times { |n| User.create!(name: "Paged #{n}", email_address: "paged#{n}@example.com", password: "long-enough") }

    get staff_users_path
    assert_select "#staff_users tbody tr", 25
    get staff_users_path(page: 2)
    assert_select "#staff_users tbody tr", User.count - 25
  end

  test "show lists all of the user's accounts with their roles" do
    user = users(:jo)
    accounts(:umbrella).memberships.create!(user:, role: :owner)

    get staff_user_path(user)

    assert_response :success
    assert_select "h1", "Jo Martin"
    assert_select "#user_details", text: /jo@example.com/
    assert_select "#user_details", text: /UTC/
    assert_select "#user_accounts tbody tr", 2
    assert_select "##{dom_id(accounts(:acme), :staff)}" do
      assert_select "a[href=?]", staff_account_path(accounts(:acme)), text: "Acme Labs"
      assert_select ".chip", text: "Member"
    end
    assert_select "##{dom_id(accounts(:umbrella), :staff)} .chip", text: "Owner"
    assert_select "a[href=?]", edit_staff_user_path(user)
  end

  test "show says when the email isn't verified" do
    users(:jo).update_column(:email_verified_at, nil)
    get staff_user_path(users(:jo))
    assert_select "#user_details", text: /Not verified/
  end

  test "edit has only the staff checkbox" do
    get edit_staff_user_path(users(:jo))

    assert_response :success
    assert_select "form input[type=checkbox][name='user[staff]']"
    assert_select "form input:not([type=hidden])", 2 # the checkbox and Save
  end

  test "staff can grant and remove another user's staff access" do
    patch staff_user_path(users(:jo)), params: { user: { staff: "1" } }
    assert_redirected_to staff_user_path(users(:jo))
    assert_equal "Jo Martin is now staff.", flash[:notice]
    assert users(:jo).reload.staff?

    patch staff_user_path(users(:jo)), params: { user: { staff: "0" } }
    assert_equal "Jo Martin is no longer staff.", flash[:notice]
    assert_not users(:jo).reload.staff?
  end

  test "only the staff flag is permitted" do
    patch staff_user_path(users(:jo)), params: { user: { staff: "1", name: "Hacked", email_address: "x@example.com" } }

    assert_equal [ "Jo Martin", "jo@example.com" ], users(:jo).reload.values_at(:name, :email_address)
  end

  test "staff can't remove their own staff access" do
    patch staff_user_path(users(:staffer)), params: { user: { staff: "0" } }

    assert_response :unprocessable_entity
    assert_select "#user_errors", text: User::SELF_DEMOTION
    assert users(:staffer).reload.staff?
  end

  test "an unknown user is a 404" do
    get staff_user_path(id: 0)
    assert_response :not_found
  end
end
