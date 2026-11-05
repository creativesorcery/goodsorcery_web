# One slow request's (or job run's) trace (docs/ARCHITECTURE.md §13.9 screen
# 3). Looked up by uuid within the app only. A trace past the retention, or
# replaced by a slower request, renders the "no longer kept" page (410);
# unknown ids are 404s.
class Projects::Performance::TracesController < ApplicationController
  include PerformanceScoped

  def show
    @lookup = Apm::TraceLookup.new(@project, params[:id], entitlements: Current.account.entitlements)
    return show_trace if @lookup.found?
    raise ActiveRecord::RecordNotFound unless @lookup.expired? && !kept_by_another_app?

    render :expired, status: :gone
  end

  private
    # A trace of another app of this account, opened under this app's slug:
    # a 404 like any other unknown id, not "no longer kept".
    def kept_by_another_app?
      ApmTrace.where(project_id: Current.account.projects.where.not(id: @project.id).select(:id))
        .exists?(uuid: Apm::TraceId.uuid(params[:id]))
    end

    def show_trace
      @selection = performance_selection(environment: @lookup.trace.apm_transaction.environment)
      @page = Apm::TracePage.new(@lookup.trace, cutoff: @lookup.cutoff)
    end
end
