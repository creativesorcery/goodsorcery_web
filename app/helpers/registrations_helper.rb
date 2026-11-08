module RegistrationsHelper
  LEGAL_PAGES = { "Terms of Service" => :terms_url, "Privacy Policy" => :privacy_url }.freeze

  # "By signing up you agree to the Terms of Service and Privacy Policy.",
  # naming only the pages whose URL is set (GOODSORCERY_TERMS_URL,
  # GOODSORCERY_PRIVACY_URL), or nil when neither is, so the sign-up page
  # shows no sentence at all. Links break out of any frame with target=_top.
  def signup_agreement
    links = LEGAL_PAGES.filter_map do |name, setting|
      url = Rails.configuration.x.public_send(setting).presence
      link_to(name, url, target: "_top", rel: "noopener", class: "text-iris-300 hover:underline") if url
    end
    return if links.empty?

    tag.p(safe_join([ "By signing up you agree to the ", safe_join(links, " and "), "." ]),
      class: "text-center text-[12.5px] text-ink-400")
  end
end
