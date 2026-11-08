require "test_helper"

class RegistrationsHelperTest < ActionView::TestCase
  TERMS = "https://example.com/terms".freeze
  PRIVACY = "https://example.com/privacy".freeze

  test "links both pages when both are set" do
    with_legal_urls(terms: TERMS, privacy: PRIVACY) { render html: signup_agreement }

    assert_select "p", text: "By signing up you agree to the Terms of Service and Privacy Policy."
    assert_select "p a", 2
    assert_select "a[href=?][target=_top][rel=noopener]", TERMS, text: "Terms of Service"
    assert_select "a[href=?][target=_top][rel=noopener]", PRIVACY, text: "Privacy Policy"
  end

  test "names only the terms when only they are set" do
    with_legal_urls(terms: TERMS) { render html: signup_agreement }

    assert_select "p", text: "By signing up you agree to the Terms of Service."
    assert_select "p a", 1
    assert_select "a[href=?][target=_top][rel=noopener]", TERMS, text: "Terms of Service"
  end

  test "names only the privacy policy when only it is set" do
    with_legal_urls(privacy: PRIVACY) { render html: signup_agreement }

    assert_select "p", text: "By signing up you agree to the Privacy Policy."
    assert_select "p a", 1
    assert_select "a[href=?][target=_top][rel=noopener]", PRIVACY, text: "Privacy Policy"
  end

  test "renders nothing when neither is set" do
    with_legal_urls { assert_nil signup_agreement }
    with_legal_urls(terms: "", privacy: "") { assert_nil signup_agreement }
  end
end
