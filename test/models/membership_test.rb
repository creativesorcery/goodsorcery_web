require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  test "roles" do
    assert memberships(:philip_acme).owner?
    assert memberships(:jo_acme).member?
    assert_not Membership.new(account: accounts(:acme), user: users(:outsider), role: "admin").valid?
  end

  test "a user joins an account only once" do
    duplicate = Membership.new(account: accounts(:acme), user: users(:jo))
    assert_not duplicate.valid?
  end

  test "removing a member ends their sessions in that account" do
    session = users(:jo).sessions.create!(account: accounts(:acme))

    memberships(:jo_acme).destroy

    assert_not Session.exists?(session.id)
    assert_not accounts(:acme).accessible_by?(users(:jo))
  end
end
