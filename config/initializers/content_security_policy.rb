# Be sure to restart your server when you modify this file.
#
# Strict policy: no inline scripts and no inline styles. Importmap and the Turbo
# progress bar receive the per-session nonce through csp_meta_tag. All charts and
# bars are server-rendered SVG built from element attributes (ChartHelper), so no
# style="" attributes are needed. Google Fonts is the only third party.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.script_src      :self
    policy.style_src       :self, "https://fonts.googleapis.com"
    policy.font_src        :self, "https://fonts.gstatic.com"
    policy.img_src         :self, :data
    policy.connect_src     :self
    policy.object_src      :none
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :none
  end

  # A per-session nonce stays stable across Turbo Drive visits, which merge <head> scripts.
  # A first visit has no session cookie yet (session.id is nil), so fall back to a random
  # nonce; an empty nonce would block importmap and Turbo on the sign-in page.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s.presence || SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
