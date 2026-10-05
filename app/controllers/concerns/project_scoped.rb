# Loads @project by slug from the signed-in account only; misses are 404s.
# Remembers it (id only) so pages without a project keep it in the sidebar.
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private
    def set_project
      @project = Current.account.projects.find_by!(slug: params[:project_id])
      session[:last_project_id] = @project.id
    end
end
