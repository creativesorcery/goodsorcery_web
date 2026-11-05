# One endpoint's (or job's) page (docs/ARCHITECTURE.md §13.9 screen 2). Only
# listed transactions of the app: total rows and other apps' ids are 404s.
# Sorting and paging the slow traces reload just their frame.
class Projects::Performance::TransactionsController < ApplicationController
  include PerformanceScoped

  def show
    @transaction = @project.apm_transactions.listed.find(params[:id])
    @selection = performance_selection(environment: @transaction.environment)
    @report = Apm::EndpointReport.new(@transaction, @selection)
    render partial: "projects/performance/transactions/traces", locals: traces_locals if traces_frame_request?
  end

  private
    def traces_frame_request? = turbo_frame_request_id == helpers.dom_id(@transaction, :traces)

    def traces_locals = { transaction: @transaction, selection: @selection, list: @report.traces }
end
