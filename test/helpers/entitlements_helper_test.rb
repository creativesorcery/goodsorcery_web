require "test_helper"

class EntitlementsHelperTest < ActionView::TestCase
  test "upgrade_to_unlock is plain text without an upgrade URL" do
    with_upgrade_url(nil) do
      render html: upgrade_to_unlock

      assert_select "span.text-iris-300", text: "Upgrade to unlock"
      assert_select "a", count: 0
    end
  end

  test "upgrade_to_unlock links to the upgrade URL in a new tab" do
    with_upgrade_url("https://billing.example/upgrade?from=uptime") do
      render html: upgrade_to_unlock

      assert_select "a[href=?][target=_blank][rel=?]", "https://billing.example/upgrade?from=uptime", "noopener noreferrer",
        text: "Upgrade to unlock"
    end
  end

  test "upgrade_to_unlock takes custom text and classes" do
    with_upgrade_url("https://billing.example/upgrade") do
      render html: upgrade_to_unlock("Upgrade for more monitors", classes: "text-ink-400")

      assert_select "a.text-ink-400.hover\\:underline", text: "Upgrade for more monitors"
    end
  end

  test "upgrade_to_unlock escapes its text" do
    with_upgrade_url(nil) do
      assert_includes upgrade_to_unlock("<b>x</b>"), "&lt;b&gt;x&lt;/b&gt;"
    end
  end

  test "entitlements come from the current account and are memoised" do
    Current.session = users(:outsider).sessions.create!(account: accounts(:umbrella))
    first = entitlements

    assert_instance_of Entitlements, first
    assert_same first, entitlements
    with_hosted_mode { assert_equal 3, Current.account.entitlements.max_monitors }
  ensure
    Current.reset
  end

  private
    def with_upgrade_url(url)
      previous = Rails.configuration.x.upgrade_url
      Rails.configuration.x.upgrade_url = url
      yield
    ensure
      Rails.configuration.x.upgrade_url = previous
    end
end
