# Loads @project and then @issue by short id ("GS-1042") within that project.
module IssueScoped
  extend ActiveSupport::Concern
  include ProjectScoped

  included do
    before_action :set_issue
  end

  private
    def set_issue
      @issue = @project.issues.find_by_short_id!(params[:issue_id])
    end
end
