module ApplicationHelper
  DEFAULT_DOCS_URL = "https://github.com/creativesorcery/goodsorcery_web/tree/main/docs".freeze

  GOOGLE_FONTS_URL = "https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500..700" \
    "&family=Figtree:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap".freeze

  PLATFORM_LABELS = { "rails" => "Ruby on Rails", "ruby" => "Ruby", "rust" => "Rust" }.freeze

  def docs_url
    ENV.fetch("GOODSORCERY_DOCS_URL", DEFAULT_DOCS_URL)
  end

  def hosted?
    Rails.configuration.x.hosted
  end

  def signups_enabled?
    return @signups_enabled if defined?(@signups_enabled)

    @signups_enabled = Signup.open?
  end

  def platform_label(platform)
    PLATFORM_LABELS.fetch(platform.to_s) { platform.to_s.humanize }
  end

  # The runtime label the client reported ("Rust 1.82 · axum 0.8") once events arrive, otherwise the platform name.
  def project_runtime_label(project)
    project.runtime_label.presence || platform_label(project.platform)
  end

  # Preconnects plus the stylesheet; allowed by the CSP (style-src/font-src).
  def google_font_tags
    safe_join [
      tag.link(rel: "preconnect", href: "https://fonts.googleapis.com"),
      tag.link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: ""),
      tag.link(rel: "stylesheet", href: GOOGLE_FONTS_URL)
    ]
  end

  # "Issues · storefront — Good Sorcery"
  def document_title
    safe_join [ content_for(:title).presence, "Good Sorcery" ].compact, " — "
  end
end
