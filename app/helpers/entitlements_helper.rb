# Views call these only when `!entitlements.unlimited?`, so self-hosted
# instances never show a locked option (docs/ARCHITECTURE.md §12.2). Whether
# a locked option offers an upgrade or says "Coming soon" is UpgradeOffer's
# call; views ask these helpers and never read the upgrade URL themselves.
module EntitlementsHelper
  LOCKED_CLASSES = "opacity-50 cursor-not-allowed".freeze

  # A link to GOODSORCERY_UPGRADE_URL, or nil when none is set: there is
  # nothing to upgrade to yet, so no upgrade text renders at all.
  def upgrade_to_unlock(text = UpgradeOffer::UPGRADE_TO_UNLOCK, classes: "text-iris-300")
    return unless upgrade_offered?

    link_to text, UpgradeOffer.url, class: [ classes, "hover:underline" ], target: "_blank", rel: "noopener noreferrer"
  end

  def upgrade_offered? = UpgradeOffer.available?

  # "Upgrade to unlock", or "Coming soon" without an upgrade URL.
  def locked_note = UpgradeOffer.locked_note

  # A greyed-out, unselectable option titled #locked_note. A span rather than
  # a disabled button, which some browsers never send hover events to.
  def locked_option(content = nil, classes: nil, aria: {}, &)
    tag.span(content, class: [ classes, LOCKED_CLASSES ], title: locked_note, aria: { disabled: "true", **aria }, &)
  end

  # Takes the place of an "add" button at a limit when no upgrade is offered.
  def coming_soon_notice(sentence, classes: "text-[13px] text-ink-400")
    tag.span(sentence, class: [ classes, "cursor-not-allowed" ], title: UpgradeOffer::COMING_SOON, aria: { disabled: "true" })
  end

  # Whether the account is at its app limit (hosted with a max_projects).
  # The count comes from the sidebar's switcher query when that holds every
  # app, so it usually costs no query of its own.
  def project_limit_reached?
    return false if Current.account.nil? || entitlements.max_projects.nil?
    return @project_limit_reached if defined?(@project_limit_reached)

    @project_limit_reached = entitlements.project_limit_reached?(account_project_count)
  end

  # Takes the place of an "Add a new app" entry point at the app limit.
  def new_app_limit_notice(classes: "text-[13px] text-ink-400")
    return coming_soon_notice(Project::LIMIT_COMING_SOON, classes:) unless upgrade_offered?

    tag.span(safe_join([ Project::LIMIT_REACHED, upgrade_to_unlock ], " "), class: classes)
  end

  def entitlements
    @entitlements ||= Current.account.entitlements
  end
end
