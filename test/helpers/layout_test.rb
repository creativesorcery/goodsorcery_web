require "test_helper"

# Renders the authenticated shell around an empty page in every state it must survive.
class LayoutTest < ActionView::TestCase
  teardown { Current.reset }

  test "signed-in shell shows the switcher, nav, quota-free account and user menu" do
    Current.session = users(:philip).sessions.create!(account: accounts(:acme))
    @project = projects(:storefront)

    render_shell nav: "issues"

    assert_select "aside a.nav-link[aria-current=page]", text: /Issues/
    assert_select "aside a[href=?]", project_issues_path(@project)
    assert_select "aside a[href=?]", project_setup_path(@project)
    assert_select "aside [data-controller=dropdown] button", text: /storefront/
    assert_select "aside a[href=?]", new_project_path, text: /Add a new app/
    assert_select "aside", text: /Uptime\s*soon/
    assert_select "aside", text: /#{Regexp.escape(users(:philip).name)}/
    assert_select "form[action=?][method=get] input[name=q]", search_path
    assert_select "header nav[aria-label=Breadcrumb]", text: /Acme Labs/
    assert_select "title", "Issues — Good Sorcery"
  end

  test "an account without projects gets an Add a new app prompt and no project links" do
    account = Account.create!(name: "Fresh Co")
    account.memberships.create!(user: users(:jo), role: :owner)
    Current.session = users(:jo).sessions.create!(account:)

    render_shell

    assert_select "aside a[href=?]", new_project_path, text: /Add a new app/
    assert_select "aside a.nav-link", text: /Issues/, count: 0
    assert_select "aside", text: /Settings & setup/, count: 0
  end

  test "renders without a current user" do
    render_shell

    assert_select "aside a.nav-link", text: /Projects/
    assert_select "aside button", text: /Sign out/, count: 0
  end

  test "the usage meter appears only when the account has a quota" do
    account = accounts(:acme)
    account.update!(monthly_event_quota: 1_000_000)
    Current.session = users(:philip).sessions.create!(account:)

    render_shell

    assert_select "aside", text: /Events this month/
    assert_select "aside svg[aria-label$=?]", "% used"
  end

  test "the sidebar's query count does not grow with the number of projects" do
    Current.session = users(:philip).sessions.create!(account: accounts(:acme))
    baseline = count_queries { render_shell }

    3.times { |n| accounts(:acme).projects.create!(name: "extra #{n}") }
    reset_view
    Current.session = users(:philip).sessions.create!(account: accounts(:acme))

    assert_equal baseline, count_queries { render_shell }
    assert_operator baseline, :<=, 3
  end

  test "the shell has no inline styles or scripts" do
    render_shell

    assert_no_match(/style="/, rendered)
    assert_select "script:not([type=importmap]):not([type=module]):not([src])", count: 0
  end

  private
    def render_shell(nav: nil)
      view.provide :title, "Issues"
      view.provide :nav, nav if nav
      view.breadcrumb "Acme Labs", projects_path
      render template: "layouts/application", layout: false, locals: {}
    end

    def reset_view
      @view = nil
      @rendered = +""
    end

    def count_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
end
