# What a hosted limit offers (docs/ARCHITECTURE.md §12.2): an upgrade when
# GOODSORCERY_UPGRADE_URL (config.x.upgrade_url) is set, and "coming soon"
# when it isn't. The one place that decides between the two: views go through
# EntitlementsHelper, and limit validations word their errors through
# .limit_message. Self-hosted instances have no limits, so never get here.
module UpgradeOffer
  UPGRADE_TO_UNLOCK = "Upgrade to unlock".freeze
  COMING_SOON = "Coming soon".freeze

  def self.url = Rails.configuration.x.upgrade_url.presence

  def self.available? = !url.nil?

  # What a locked option says on hover and in its label.
  def self.locked_note = available? ? UPGRADE_TO_UNLOCK : COMING_SOON

  # A limit error: the limit sentence when an upgrade is on offer, else the
  # coming-soon sentence.
  def self.limit_message(limit_sentence, coming_soon:) = available? ? limit_sentence : coming_soon
end
