require "test_helper"

# Every /staff route answers 404, exactly like a path that doesn't exist, to
# signed-out visitors and signed-in users who aren't staff.
class Staff::AccessTest < ActionDispatch::IntegrationTest
  ROUTES = [
    [ :get, -> { staff_root_path } ],
    [ :get, -> { staff_accounts_path } ],
    [ :get, -> { staff_account_path(accounts(:acme)) } ],
    [ :get, -> { edit_staff_account_path(accounts(:acme)) } ],
    [ :patch, -> { staff_account_path(accounts(:acme)) } ],
    [ :get, -> { staff_users_path } ],
    [ :get, -> { staff_user_path(users(:philip)) } ],
    [ :get, -> { edit_staff_user_path(users(:philip)) } ],
    [ :patch, -> { staff_user_path(users(:philip)) } ]
  ].freeze

  IE11_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko".freeze

  PARAMS = { entitlements: { max_monitors: "99", setting: { max_monitors: "custom" } }, user: { staff: "1" } }.freeze

  test "signed out, every staff route is a 404, not a sign-in redirect" do
    assert_every_route_not_found
  end

  test "signed in without staff, every staff route is a 404" do
    sign_in_as users(:philip)
    assert_every_route_not_found
  end

  test "with forgery protection on, as in production, a write without a token is a 404, not a CSRF 422" do
    with_forgery_protection do
      [ nil, users(:philip) ].each do |user|
        user ? sign_in_as(user) : reset!
        patch staff_account_path(accounts(:acme)), params: PARAMS
        assert_response :not_found, "PATCH as #{user&.name || 'signed out'}"
        put staff_user_path(users(:philip)), params: PARAMS
        assert_response :not_found, "PUT as #{user&.name || 'signed out'}"
      end
    end
  end

  test "an old browser without staff gets a 404, not the unsupported-browser 406" do
    sign_in_as users(:philip)
    get staff_accounts_path, headers: { "User-Agent" => IE11_USER_AGENT }

    assert_response :not_found
  end

  test "a missing id is a 404 for non-staff too, so ids can't be probed" do
    sign_in_as users(:outsider)
    get staff_account_path(id: 0)
    assert_response :not_found
  end

  test "non-staff can't change anything through the staff routes" do
    sign_in_as users(:philip)
    patch staff_user_path(users(:philip)), params: PARAMS
    patch staff_account_path(accounts(:acme)), params: PARAMS

    assert_not users(:philip).reload.staff?
    assert_equal({}, accounts(:acme).reload.entitlement_values)
  end

  test "staff pages are never cached and aren't account-scoped" do
    sign_in_as users(:staffer)
    get staff_account_path(accounts(:umbrella))

    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "the user menu links to the staff area for staff only" do
    sign_in_as users(:philip)
    get projects_path
    assert_select "a[href=?]", staff_root_path, count: 0

    sign_in_as users(:staffer)
    get projects_path
    assert_select "a.menu-item[href=?]", staff_root_path, text: "Staff"
  end

  private
    def with_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    def assert_every_route_not_found
      ROUTES.each do |verb, path|
        send(verb, instance_exec(&path), params: (PARAMS if verb == :patch))
        assert_response :not_found, "#{verb.upcase} #{instance_exec(&path)}"
      end
    end
end
