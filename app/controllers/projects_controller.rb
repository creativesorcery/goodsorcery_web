# Projects overview, "Add a new app" and Settings › General.
class ProjectsController < ApplicationController
  before_action :set_project, only: %i[edit update]

  def index
    @overview = ProjectOverview.new(Current.account.projects.order(:name))
    @feed = RecentFeed.new(Current.account)
  end

  def new
    @project = Current.account.projects.new
  end

  def create
    @project = Current.account.projects.new(new_project_params)

    if @project.save
      redirect_to project_setup_path(@project), notice: "#{@project.name} is ready. Let's connect it."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to edit_project_path(@project), notice: "Settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_project
      @project = Current.account.projects.find_by!(slug: params[:id])
    end

    def new_project_params
      params.expect(project: %i[name platform])
    end

    # scrub_fields arrives as a comma separated list.
    def project_params
      params.expect(project: %i[name platform issue_prefix scrub_fields retention_days]).tap do |attributes|
        attributes[:scrub_fields] = attributes[:scrub_fields].to_s.split(",") if attributes.key?(:scrub_fields)
      end
    end
end
