# The "and N more alerts in the last hour" post for an app's issue alerts
# folded over SlackDelivery::HOURLY_CAP: counts per kind only.
class SlackMessage::Summary < SlackMessage
  # counts: { "new_issue" => 3, "regression" => 1 }
  def initialize(project, counts)
    @project, @counts = project, counts.to_h.transform_values(&:to_i)
  end

  private
    attr_reader :project, :counts

    def total = counts.values.sum

    def fallback_text
      escape("And #{count(total, 'more alert')} in #{project.name} in the last hour")
    end

    def blocks
      [ section("*And #{count(total, 'more alert')}* in *#{escape(project.name)}* in the last hour\n#{breakdown}"),
        button("Open #{project.name.truncate(40)} issues", project_issues_url(project)) ]
    end

    # "New issue: 3 · Regression: 1", in rule order.
    def breakdown
      counts.sort_by { |kind, _| AlertRule::KINDS.index(kind).to_i }
        .map { |kind, number| "#{escape(kind_label(kind))}: #{number.to_fs(:delimited)}" }.join(" · ")
    end
end
