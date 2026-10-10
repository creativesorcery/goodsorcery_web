# Building blocks for HTML email, shared by every mailer (see
# layouts/mailer.html.erb). Email clients support <style> blocks and modern
# CSS unevenly, so layout uses tables and every style is inline. Colors are
# the app's theme tokens (app/assets/tailwind/application.css).
module MailerHelper
  EMAIL_COLORS = { paper: "#f7f6f3", card: "#ffffff", border: "#e7e5df", heading: "#23253a", text: "#34374d",
                   muted: "#80849a", accent: "#5a5fd6", sigil: "#5b60d1", sigil_bg: "#e4e6ff" }.freeze

  EMAIL_FONT = "Figtree, -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif".freeze

  EMAIL_STYLES = {
    heading: "margin: 0 0 12px; font-size: 22px; line-height: 1.3; font-weight: 700; letter-spacing: -0.01em; color: #{EMAIL_COLORS[:heading]};",
    text: "margin: 0 0 16px; font-size: 15px; line-height: 1.6; color: #{EMAIL_COLORS[:text]};",
    note: "margin: 0 0 12px; font-size: 13px; line-height: 1.55; color: #{EMAIL_COLORS[:muted]};",
    button_cell: "border-radius: 10px; background: #{EMAIL_COLORS[:accent]};",
    button_link: "display: inline-block; padding: 13px 24px; font-size: 15px; font-weight: 600; line-height: 1; " \
                 "color: #ffffff; text-decoration: none; border-radius: 10px;",
    link: "color: #{EMAIL_COLORS[:accent]}; word-break: break-all;",
    divider: "border: 0; border-top: 1px solid #{EMAIL_COLORS[:border]}; margin: 24px 0;"
  }.freeze

  def email_heading(text)
    tag.h1 text, style: EMAIL_STYLES[:heading]
  end

  def email_text(text = nil, &)
    tag.p text, style: EMAIL_STYLES[:text], &
  end

  def email_note(text = nil, &)
    tag.p text, style: EMAIL_STYLES[:note], &
  end

  def email_divider
    tag.hr style: EMAIL_STYLES[:divider]
  end

  # A "bulletproof" button: the table cell carries the color, so it still
  # shows as a button in clients that ignore the link's padding.
  def email_button(label, url)
    link = link_to(label, url, style: EMAIL_STYLES[:button_link], target: "_blank", rel: "noopener")
    email_table(style: "margin: 8px 0 24px;") do
      tag.tr { tag.td(link, bgcolor: EMAIL_COLORS[:accent], style: EMAIL_STYLES[:button_cell]) }
    end
  end

  # The button's link spelled out, for clients that block buttons and for
  # readers who'd rather paste it.
  def email_link_fallback(url)
    email_note do
      safe_join([ "If the button doesn't work, paste this link into your browser:", tag.br,
                  link_to(url, url, style: EMAIL_STYLES[:link], target: "_blank", rel: "noopener") ])
    end
  end

  def email_table(**options, &)
    tag.table(role: "presentation", cellspacing: 0, cellpadding: 0, border: 0, **options, &)
  end
end
