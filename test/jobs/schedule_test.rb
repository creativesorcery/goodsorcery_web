require "test_helper"

class ScheduleTest < ActiveSupport::TestCase
  test "every scheduled job class exists and every cron line parses" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))

    assert_equal %w[prune_expired_data requeue_stale_events check_still_happening send_daily_digests send_alert_summaries
                   cap_stored_occurrences trim_apm_traces schedule_uptime_checks], schedule.keys
    schedule.each_value do |entry|
      assert entry["class"].constantize < ApplicationJob
      assert Fugit::Cron.parse(entry["cron"]), "unparseable cron: #{entry["cron"]}"
    end
  end
end
