# Per-address throttling of sign-in on top of the per-IP limit. Only wrong
# passwords count (FailedSignIns), and once an address has too many, sign-in
# to it is refused for the window, except from a browser that has signed in
# to that address before (an encrypted cookie holding the address's HMAC).
# So an attacker's guesses from other IPs can slow down a new browser but
# never lock the real user out of the ones they already use. A completed
# password reset remembers its browser too (PasswordsController#update): the
# reset link proved the inbox, so a locked-out user can always get back in.
module SignInThrottling
  extend ActiveSupport::Concern
  include EmailRateLimited

  KNOWN_BROWSER_COOKIE = :known_sign_ins
  KNOWN_BROWSER_LIMIT = 5 # addresses remembered per browser
  KNOWN_BROWSER_LIFETIME = 1.year

  private
    def sign_in_throttled?
      failed_sign_ins.exceeded? && !known_browser?
    end

    def record_failed_sign_in
      failed_sign_ins.record
    end

    def remember_browser_for(email_address)
      digest = FailedSignIns.new(email_address).digest
      digests = [ digest, *known_sign_in_digests ].uniq.first(KNOWN_BROWSER_LIMIT)
      cookies.encrypted[KNOWN_BROWSER_COOKIE] = { value: digests, expires: KNOWN_BROWSER_LIFETIME, httponly: true, same_site: :lax }
    end

    def known_browser?
      known_sign_in_digests.include?(failed_sign_ins.digest)
    end

    def known_sign_in_digests
      Array(cookies.encrypted[KNOWN_BROWSER_COOKIE]).grep(String)
    end

    def failed_sign_ins
      @failed_sign_ins ||= FailedSignIns.new(email_address_param)
    end
end
