require "test_helper"

class NavigationHelperTest < ActionView::TestCase
  include NavigationHelper, ::NumberHelper, IconHelper, ApplicationHelper, EnvironmentsHelper, Turbo::StreamsHelper

  teardown { Current.reset }

  test "breadcrumbs collect in order" do
    breadcrumb "Acme Labs", "/projects"
    breadcrumb "Issues"

    assert_equal [ [ "Acme Labs", "/projects" ], [ "Issues", nil ] ], breadcrumbs.map { |crumb| [ crumb.label, crumb.path ] }
  end

  test "nav_link_to marks the current section" do
    provide :nav, "issues"

    assert_includes nav_link_to("Issues", "/issues", key: "issues", icon: :issues), %(aria-current="page")
    assert_not_includes nav_link_to("Projects", "/projects", key: "projects", icon: :projects), "aria-current"
  end

  test "nav_badge hides zero" do
    assert_nil nav_badge(0)
    assert_includes nav_badge(1_240), "1.2k"
  end

  test "nav_placeholder is not a link" do
    placeholder = nav_placeholder("Uptime", icon: :uptime, note: "soon")

    assert_not_includes placeholder, "href"
    assert_includes placeholder, "soon"
  end

  test "sidebar helpers are empty without a signed-in account" do
    assert_equal [], sidebar_projects
    assert_nil sidebar_project
    assert_equal 0, sidebar_unresolved_count
  end

  test "sidebar_projects loads the switcher in one query with each first environment" do
    sign_in_to accounts(:acme)

    projects = assert_queries_count(1) { sidebar_projects }

    assert_equal accounts(:acme).projects.order(:name).pluck(:name), projects.map(&:name)
    assert_equal "production", projects.find { |project| project.id == projects(:storefront).id }.first_environment
    assert_not_includes projects.map(&:id), projects(:umbrella_app).id
  end

  test "sidebar_project prefers the page's project" do
    sign_in_to accounts(:acme)
    @project = projects(:storefront)

    assert_equal projects(:storefront), sidebar_project
  end

  test "sidebar_project falls back to the most recently active project and ignores unsaved projects" do
    sign_in_to accounts(:acme)
    @project = Project.new
    latest = Issue.where(project: accounts(:acme).projects).order(last_seen_at: :desc).first.project

    assert_equal latest, sidebar_project
  end

  test "sidebar_project keeps the project last viewed" do
    sign_in_to accounts(:acme)
    session[:last_project_id] = projects(:marketing).id

    assert_equal projects(:marketing), sidebar_project
  end

  test "a remembered project of another account is ignored" do
    sign_in_to accounts(:acme)
    session[:last_project_id] = projects(:umbrella_app).id

    assert_equal accounts(:acme), sidebar_project.account
  end

  test "sidebar_unresolved_count counts the sidebar project's unresolved issues" do
    sign_in_to accounts(:acme)
    @project = projects(:storefront)

    assert_equal projects(:storefront).issues.unresolved.count, sidebar_unresolved_count
  end

  test "sidebar_project_subtitle joins environment and runtime" do
    sign_in_to accounts(:acme)
    project = projects(:storefront)

    subtitle = sidebar_project_subtitle(project)
    assert_equal [ "production", project_runtime_label(project) ].join(" · "), strip_tags(subtitle)
    assert_includes subtitle, %(<span class="text-coral-300">production</span>)
  end

  test "live_stream_from subscribes through the authorised channel" do
    source = live_stream_from(projects(:storefront), :issues)

    assert_includes source, "turbo-cable-stream-source"
    assert_includes source, %(channel="AuthorizedStreamsChannel")
  end

  private
    def sign_in_to(account)
      user = account.memberships.order(:id).first.user
      Current.session = user.sessions.create!(account:)
    end
end
