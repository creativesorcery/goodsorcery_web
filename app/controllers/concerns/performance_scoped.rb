# The Performance pages (docs/ARCHITECTURE.md §13.8, §13.10): the app comes
# from the signed-in account (ProjectScoped), so other accounts' apps are
# 404s before anything here runs, and the shared query params are read once
# into an Apm::Selection. Any member of the account may view these pages.
# They are static: no live updates.
module PerformanceScoped
  extend ActiveSupport::Concern

  included do
    include ProjectScoped
  end

  private
    def performance_selection(environment: nil)
      Apm::Selection.new(@project, params, entitlements: Current.account.entitlements, environment:)
    end
end
