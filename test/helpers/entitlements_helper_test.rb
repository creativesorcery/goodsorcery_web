require "test_helper"

class EntitlementsHelperTest < ActionView::TestCase
  test "upgrade_to_unlock renders nothing without an upgrade URL" do
    with_upgrade_url(nil) do
      assert_nil upgrade_to_unlock
      assert_nil upgrade_to_unlock("Upgrade to keep more days")
      assert_not upgrade_offered?
    end
    with_upgrade_url("") { assert_nil upgrade_to_unlock }
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
    with_upgrade_url do
      assert_includes upgrade_to_unlock("<b>x</b>"), "&lt;b&gt;x&lt;/b&gt;"
    end
  end

  test "locked options say Coming soon without an upgrade URL and Upgrade to unlock with one" do
    with_upgrade_url(nil) { assert_equal "Coming soon", locked_note }
    with_upgrade_url { assert_equal "Upgrade to unlock", locked_note }
  end

  test "locked_option is a greyed-out span titled with the note, not a disabled button" do
    with_upgrade_url(nil) do
      render html: locked_option("7d", classes: "inline-flex", aria: { label: "7 days, coming soon" })
    end

    assert_select "span.inline-flex.opacity-50.cursor-not-allowed[title='Coming soon'][aria-disabled=true][aria-label=?]",
      "7 days, coming soon", text: "7d"
    assert_select "button, a", count: 0
  end

  test "coming_soon_notice is greyed-out text titled Coming soon" do
    render html: coming_soon_notice("Cannot add more yet, but it's coming soon")

    assert_select "span.text-ink-400.cursor-not-allowed[title='Coming soon'][aria-disabled=true]",
      text: "Cannot add more yet, but it's coming soon"
  end

  test "UpgradeOffer words limit errors by whether an upgrade URL is set" do
    with_upgrade_url(nil) { assert_equal "soon", UpgradeOffer.limit_message("limit", coming_soon: "soon") }
    with_upgrade_url { assert_equal "limit", UpgradeOffer.limit_message("limit", coming_soon: "soon") }
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
end
