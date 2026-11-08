# The Uptime pages of an app (docs/ARCHITECTURE.md §12.8): the monitor list,
# a monitor's detail page, and adding, editing and deleting monitors. Any
# member of the account may manage monitors, like Settings › General;
# creating one needs a confirmed email, since a monitor makes outbound
# requests. Entitlements are enforced by UptimeMonitor's validations; the
# views only reflect them.
class Projects::UptimeMonitorsController < ApplicationController
  include ProjectScoped
  include VerifiedEmailRequired

  require_verified_email only: %i[new create]
  before_action :set_uptime_monitor, only: %i[show edit update destroy]
  before_action :set_monitor_limit, only: %i[index new create]

  def index
    @overview = UptimeOverview.new(@project.uptime_monitors.order(:name, :id))
  end

  def show
    @report = UptimeReport.new(@uptime_monitor)
  end

  def new
    @uptime_monitor = @project.uptime_monitors.new(interval_minutes: Current.account.entitlements.default_uptime_interval)
  end

  def create
    @uptime_monitor = @project.uptime_monitors.new(uptime_monitor_params)

    if @uptime_monitor.save
      redirect_to project_uptime_monitor_path(@project, @uptime_monitor), notice: "Added #{@uptime_monitor.name}. Its first check runs within a minute."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @uptime_monitor.update(uptime_monitor_params)
      redirect_to project_uptime_monitor_path(@project, @uptime_monitor), notice: "Saved #{@uptime_monitor.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @uptime_monitor.destroy!
    redirect_to project_uptime_monitors_path(@project), status: :see_other, notice: "Deleted #{@uptime_monitor.name}."
  end

  private
    def set_uptime_monitor
      @uptime_monitor = @project.uptime_monitors.find(params[:id])
    end

    # The app's monitor count and whether it is at its limit (max_monitors
    # is per app); counted only when hosted (self-hosted has no limit).
    def set_monitor_limit
      entitlements = Current.account.entitlements
      return if entitlements.unlimited?

      @monitor_count = @project.uptime_monitors.count
      @monitor_limit_reached = entitlements.monitor_limit_reached?(@monitor_count)
    end

    def uptime_monitor_params
      params.expect(uptime_monitor: %i[name url interval_minutes])
    end
end
