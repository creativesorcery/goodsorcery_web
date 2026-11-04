# A monitor's detail report, re-fetched by live updates after each check
# (frame dom_id(monitor, :report)). It shows the full URL, like the page.
class Projects::UptimeMonitors::ReportsController < ApplicationController
  include UptimeMonitorScoped

  def show
    @report = UptimeReport.new(@uptime_monitor)
  end
end
