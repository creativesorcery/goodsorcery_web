# The staff area's pages (app/views/staff, layouts/staff).
module StaffHelper
  EntitlementRow = Data.define(:key, :label, :value, :source)

  ENTITLEMENT_SOURCES = { stored: "Stored", default: "Default", invalid: "Default (the stored value is invalid)" }.freeze

  TABLE_HEAD_CLASSES = "text-left text-[11px] uppercase tracking-[.16em] text-ink-400/80 bg-paper-850/60 border-b border-paper-700".freeze

  # Pagy's previous / page / next links (styled by .pagy in application.css),
  # or nothing on a single page. Pagy builds the markup itself: page numbers,
  # fixed labels and URLs it escapes; no user data.
  def staff_pagination(pagy)
    return if pagy.last <= 1

    pagy.series_nav(aria_label: "Pages").html_safe
  end

  # "Nov 9, 2026" in the viewer's time zone.
  def staff_date(time)
    time&.in_time_zone&.strftime("%b %-d, %Y") || "—"
  end

  def staff_entitlement_label(key)
    Staff::EntitlementsForm::LABELS.fetch(key)
  end

  # A resolved entitlement for people: "10, 60 minutes", "No limit", "3,000", "30 days".
  def staff_entitlement_value(key, value)
    return "No limit" if value.nil?

    case key
    when "uptime_intervals" then "#{value.to_sentence(two_words_connector: ', ', last_word_connector: ', ')} #{'minute'.pluralize(value.last)}"
    when "retention_days" then "#{value.to_sentence(two_words_connector: ', ', last_word_connector: ', ')} #{'day'.pluralize(value.last)}"
    when "apm_retention_days" then pluralize(value, "day")
    else number_with_delimiter(value)
    end
  end

  # The ids describing a field: its problem, when it has one, and its hint.
  def staff_entitlement_describedby(form, key)
    [ ("#{key}_error" if form.problem(key)), "#{key}_hint" ].compact.join(" ")
  end

  def staff_entitlement_default(form, key)
    staff_entitlement_value(key, form.hosted_defaults.public_send(key))
  end

  # What applies to the form's account in hosted mode, key by key in the
  # form's order, and where it comes from.
  def staff_entitlement_rows(form)
    Staff::EntitlementsForm::KEYS.map do |key|
      EntitlementRow.new(key:, label: staff_entitlement_label(key), value: staff_entitlement_value(key, form.hosted_value(key)),
                         source: ENTITLEMENT_SOURCES.fetch(form.source(key)))
    end
  end

  def staff_role_chip(membership)
    chip membership.role.humanize, tone: membership.owner? ? :iris : :neutral, small: true
  end
end
