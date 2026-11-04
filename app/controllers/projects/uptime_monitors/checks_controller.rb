# "Check now" on a monitor's page. Rate limited per user, and gated per
# monitor by UptimeMonitor::Checking#check_soon (one check per
# check_now_gap: 30 seconds, or the account's shortest uptime interval).
# The job takes the monitor's id only.
class Projects::UptimeMonitors::ChecksController < ApplicationController
  include UptimeMonitorScoped

  rate_limit to: 10, within: 1.minute, by: -> { Current.user.id }, name: "uptime_check_now", store: Ingest::RateLimitStore,
             with: -> { redirect_back_or_to project_uptime_monitor_path(@project, @uptime_monitor), alert: "Too many checks. Try again in a minute." }

  def create
    redirect_back_or_to project_uptime_monitor_path(@project, @uptime_monitor), **check_outcome
  end

  private
    def check_outcome
      return { alert: "#{@uptime_monitor.name} is paused, so it isn't checked." } if @uptime_monitor.paused?
      return { alert: "Checked less than #{@uptime_monitor.check_now_gap.inspect} ago." } unless @uptime_monitor.check_soon

      UptimeCheckJob.perform_later(@uptime_monitor.id)
      { notice: "Checking #{@uptime_monitor.name} now…" }
    end
end
