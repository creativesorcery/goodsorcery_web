require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "hosted? reads the hosted-mode config and is off by default" do
    assert_not hosted?
    with_hosted_mode { assert hosted? }
    with_hosted_mode(false) { assert_not hosted? }
  end

  test "signups_enabled? is closed by default once an account exists" do
    with_env("GOODSORCERY_ENABLE_SIGNUPS" => nil, "GOODSORCERY_DISABLE_SIGNUPS" => nil) { assert_not signups_enabled? }
  end

  test "signups_enabled? opens with GOODSORCERY_ENABLE_SIGNUPS unless disabled" do
    with_env("GOODSORCERY_ENABLE_SIGNUPS" => "1", "GOODSORCERY_DISABLE_SIGNUPS" => nil) { assert Signup.open? }
    with_env("GOODSORCERY_ENABLE_SIGNUPS" => "1", "GOODSORCERY_DISABLE_SIGNUPS" => "1") { assert_not Signup.open? }
  end

  test "the first account can always sign up unless disabled" do
    Account.delete_all
    with_env("GOODSORCERY_ENABLE_SIGNUPS" => nil, "GOODSORCERY_DISABLE_SIGNUPS" => nil) { assert Signup.open? }
    with_env("GOODSORCERY_DISABLE_SIGNUPS" => "1") { assert_not Signup.open? }
  end

  test "docs_url can be overridden" do
    with_env("GOODSORCERY_DOCS_URL" => "https://docs.example.test") { assert_equal "https://docs.example.test", docs_url }
  end

  test "platform and runtime labels" do
    assert_equal "Ruby on Rails", platform_label("rails")
    assert_equal "Ruby", platform_label("ruby")
    assert_equal "Rails 8.0 · Ruby 3.4", project_runtime_label(Project.new(platform: "rails", runtime_label: "Rails 8.0 · Ruby 3.4"))
    assert_equal "Ruby on Rails", project_runtime_label(Project.new(platform: "rails"))
  end

  test "document_title appends the product name without double escaping" do
    assert_equal "Good Sorcery", document_title
    provide :title, "Setup & keys"
    assert_equal "Setup &amp; keys — Good Sorcery", document_title
  end

  test "google_font_tags only point at Google Fonts" do
    assert_equal 3, google_font_tags.scan("<link").size
    assert_includes google_font_tags, "fonts.gstatic.com"
  end

  private
    def with_env(values)
      previous = values.keys.index_with { |key| ENV[key] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
end
