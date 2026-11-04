# Views call these only when `!entitlements.unlimited?`, so self-hosted
# instances never show a locked option (docs/ARCHITECTURE.md §12.2).
module EntitlementsHelper
  UPGRADE_TO_UNLOCK = "Upgrade to unlock".freeze

  # A link to GOODSORCERY_UPGRADE_URL when it is set, plain text otherwise.
  def upgrade_to_unlock(text = UPGRADE_TO_UNLOCK, classes: "text-iris-300")
    url = Rails.configuration.x.upgrade_url
    return tag.span(text, class: classes) if url.blank?

    link_to text, url, class: [ classes, "hover:underline" ], target: "_blank", rel: "noopener noreferrer"
  end

  def entitlements
    @entitlements ||= Current.account.entitlements
  end
end
