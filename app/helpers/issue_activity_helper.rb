# The issue page's activity timeline.
module IssueActivityHelper
  def activity_marker(activity)
    case activity.kind
    when "resolved" then tag.span("✓", class: "text-mint-300")
    when "regressed" then tag.span("↺", class: "text-lilac-300")
    when "note" then tag.span("✎", class: "text-ink-300")
    when "assigned", "unassigned", "reopened" then tag.span("✦", class: "text-iris-400")
    else tag.span("○", class: "text-ink-400")
    end
  end

  # "Philip assigned themselves", "Jo resolved this", "Regressed after being resolved"
  def activity_sentence(activity)
    return "Regressed: seen again after being resolved" if activity.regressed?

    safe_join([ tag.span(activity_actor(activity), class: "text-ink-100"), " ", activity_action(activity) ])
  end

  private
    def activity_actor(activity)
      activity.user&.first_name || "A former member"
    end

    def activity_action(activity)
      case activity.kind
      when "assigned" then "assigned #{activity_subject(activity)}"
      when "unassigned" then "unassigned #{activity_subject(activity)}"
      when "note" then "left a note"
      else "#{activity.kind} this"
      end
    end

    def activity_subject(activity)
      return "themselves" if activity.subject_user_id.present? && activity.subject_user_id == activity.user_id

      activity.subject_user&.first_name || "a former member"
    end
end
