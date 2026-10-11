require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:philip)
  end

  test "requires sign in" do
    sign_out

    get projects_path

    assert_redirected_to new_session_path
  end

  test "overview lists the account's projects as cards" do
    get root_path

    assert_response :success
    assert_select "h1", text: /Projects\s+— 3/
    assert_select "a.btn-primary[href=?]", new_project_path, text: /Add a new app/
    assert_select "turbo-frame##{dom_id(projects(:storefront), :card)}"
    assert_select "turbo-frame##{dom_id(projects(:billing), :card)}"
    assert_select "turbo-frame##{dom_id(projects(:marketing), :card)}"
    assert_no_match "umbrella-app", response.body
  end

  test "cards show counts, sparkline, environments and last error" do
    get projects_path

    assert_select "turbo-frame##{dom_id(projects(:storefront), :card)}" do
      assert_select "a[href=?]", project_issues_path(projects(:storefront))
      assert_select ".font-display", text: projects(:storefront).issues.unresolved.count.to_s
      assert_select "span.text-coral-300", text: "1 new"
      assert_select "svg path", minimum: 2
      assert_select ".chip.chip-coral", text: "production"
      assert_select ".chip.chip-lilac", text: "staging"
      assert_select "span", text: "last error 2 min ago"
    end
  end

  test "a project waiting for its first event links to setup and is listening" do
    get projects_path

    assert_select "turbo-frame##{dom_id(projects(:marketing), :card)}" do
      assert_select "a.border-dashed[href=?]", project_setup_path(projects(:marketing))
      assert_select ".chip", text: "Listening…"
      assert_select "*", text: /Waiting for the first event to arrive/
      assert_select "*", text: /Finish setup/
      assert_select "svg", count: 0
    end
  end

  test "a project with nothing unresolved is all clear" do
    issues(:billing_timeout).update_columns(status: "resolved")

    get projects_path

    assert_select "turbo-frame##{dom_id(projects(:billing), :card)}" do
      assert_select ".chip-mint", text: "✦ All clear"
      assert_select ".text-mint-300", text: "0"
      assert_select "*", text: /0 days clean/
    end
  end

  test "overview has the add a new app tile, the recent feed and the live stream" do
    get projects_path

    assert_select "a[href=?]", new_project_path, text: /One gem, one key, two minutes/
    assert_select "turbo-frame##{dom_id(accounts(:acme), :recent_issues)}" do
      assert_select "li", minimum: 1
      assert_select "a[href=?]", project_issue_path(projects(:storefront), issues(:nomethod))
    end
    assert_select "turbo-cable-stream-source[channel=AuthorizedStreamsChannel]"
  end

  test "overview has no greeting or needs-attention callout" do
    get projects_path

    assert_no_match(/needs attention|good morning|good evening/i, response.body)
  end

  test "overview runs a fixed number of queries" do
    get projects_path
    baseline = count_queries { get projects_path }

    Project.create!(account: accounts(:acme), name: "another-app")
    Project.create!(account: accounts(:acme), name: "yet-another-app")

    assert_equal baseline, count_queries { get projects_path }
  end

  test "new shows the add a new app form" do
    get new_project_path

    assert_response :success
    assert_select "title", text: /Add a new app/
    assert_select "h1", "Add a new app"
    assert_select "form[action=?][method=post]", projects_path do
      assert_select "input[name=?]", "project[name]"
      assert_select "select[name=?]", "project[platform]" do
        assert_select "option", count: 2
        assert_select "option[value=rails][selected]", "Ruby on Rails"
        assert_select "option[value=ruby]", "Ruby"
      end
      assert_select "input[type=submit][value=?]", "Add a new app"
    end
  end

  test "create adds a project with default keys and redirects to setup" do
    assert_difference -> { accounts(:acme).projects.count } => 1, -> { ApiKey.count } => 2 do
      post projects_path, params: { project: { name: "Checkout Web", platform: "ruby" } }
    end

    project = accounts(:acme).projects.find_by!(slug: "checkout-web")
    assert_redirected_to project_setup_path(project)
    assert_predicate project, :ruby?
    assert_predicate project, :listening?
    assert_equal [ users(:philip) ], project.api_keys.map(&:created_by).uniq
  end

  test "create ignores attributes that are not allowed" do
    post projects_path, params: { project: { name: "sneaky", account_id: accounts(:umbrella).id, issues_sequence: 99 } }

    project = Project.find_by!(slug: "sneaky")
    assert_equal accounts(:acme), project.account
    assert_equal 0, project.issues_sequence
  end

  test "create with an invalid name re-renders the form" do
    assert_no_difference -> { Project.count } do
      post projects_path, params: { project: { name: " ", platform: "rails" } }
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Name can't be blank/
  end

  test "edit shows general settings" do
    get edit_project_path(projects(:storefront))

    assert_response :success
    assert_select "nav[aria-label='Project settings'] a[aria-current=page]", "General"
    assert_select "form[action=?]", project_path(projects(:storefront)) do
      assert_select "select[name=?] option[selected]", "project[platform]", "Ruby on Rails"
      assert_select "input[name=?][value=?]", "project[issue_prefix]", "GS"
      assert_select "input[name=?][value=?]", "project[scrub_fields]", "loyalty_number"
      assert_select "input[name=?][value=?]", "project[retention_days]", "90"
    end
  end

  test "update saves general settings and splits scrub fields" do
    patch project_path(projects(:storefront)), params: { project: {
      name: "Storefront Web", platform: "ruby", issue_prefix: "sf", scrub_fields: "Passport, loyalty_number, ,iban", retention_days: "30"
    } }

    project = projects(:storefront).reload
    assert_redirected_to edit_project_path(project)
    assert_equal "Storefront Web", project.name
    assert_equal "storefront", project.slug
    assert_predicate project, :ruby?
    assert_equal "SF", project.issue_prefix
    assert_equal %w[passport loyalty_number iban], project.scrub_fields
    assert_equal 30, project.retention_days
  end

  test "update with invalid values re-renders with the saved name in the breadcrumb" do
    patch project_path(projects(:storefront)), params: { project: { name: "", retention_days: "999" } }

    assert_response :unprocessable_entity
    assert_select "header nav a", text: "storefront"
    assert_select "[role=alert]", text: /Retention days/
    assert_equal 90, projects(:storefront).reload.retention_days
  end

  test "outsiders get 404 for another account's project settings" do
    sign_in_as users(:outsider)

    get edit_project_path(projects(:storefront))
    assert_response :not_found

    patch project_path(projects(:storefront)), params: { project: { name: "pwned" } }
    assert_response :not_found
    assert_equal "storefront", projects(:storefront).reload.name
  end

  test "outsiders only see their own projects" do
    sign_in_as users(:outsider)

    get projects_path

    assert_select "turbo-frame##{dom_id(projects(:umbrella_app), :card)}"
    assert_select "turbo-frame##{dom_id(projects(:storefront), :card)}", count: 0
    assert_no_match "price_cents", response.body
  end

  test "dashboard responses are not stored" do
    get projects_path

    assert_equal "no-store", response.headers["Cache-Control"]
  end

  private
    def count_queries(&block)
      count = 0
      callback = ->(*, payload) { count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
      count
    end
end
