# Loads @project by slug from the signed-in account only; misses are 404s.
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private
    def set_project
      @project = Current.account.projects.find_by!(slug: params[:project_id])
    end
end
