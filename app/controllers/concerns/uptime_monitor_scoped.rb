# Loads @project and then @uptime_monitor by id within that project, so a
# monitor of another app or account is a 404.
module UptimeMonitorScoped
  extend ActiveSupport::Concern
  include ProjectScoped

  included do
    before_action :set_uptime_monitor
  end

  private
    def set_uptime_monitor
      @uptime_monitor = @project.uptime_monitors.find(params[:uptime_monitor_id])
    end
end
