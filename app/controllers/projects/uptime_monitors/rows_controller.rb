# One monitor's row on the Uptime page, re-fetched by live updates after each
# check (frame dom_id(monitor, :row)).
class Projects::UptimeMonitors::RowsController < ApplicationController
  include UptimeMonitorScoped

  def show
    @row = UptimeOverview.new([ @uptime_monitor ]).rows.first
  end
end
