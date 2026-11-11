# Be sure to restart your server when you modify this file.
#
# Strict policy: no inline scripts and no inline styles. Importmap and the Turbo
# progress bar receive the per-response nonce through csp_meta_tag. All charts and
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

  # A fresh random nonce for every response, never derived from the session: a nonce that
  # leaked once (say through an HTML-injection bug) must not stay valid for the browser's
  # whole session. Rails generates it once per request, so the header, csp_meta_tag and the
  # importmap tags all carry the same value. Turbo Drive compares <head> elements with their
  # nonce blanked (elementWithoutNonce), so a new nonce on each visit neither re-runs the
  # importmap scripts nor forces a full reload; there are no inline scripts in <body>.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
