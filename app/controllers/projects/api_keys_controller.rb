# Ingest keys on the setup page: a masked row (show, also used by "Hide") and
# a new key for another environment (create).
class Projects::ApiKeysController < ApplicationController
  include ProjectScoped

  def show
    @api_key = @project.api_keys.find(params[:id])
    render layout: false
  end

  def create
    @api_key = @project.api_keys.new(environment: params.dig(:api_key, :environment).to_s, created_by: Current.user)

    if @api_key.save
      respond_to_created
    else
      respond_to_invalid
    end
  end

  private
    def respond_to_created
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to project_setup_path(@project), notice: "Added a #{@api_key.environment} key." }
      end
    end

    def respond_to_invalid
      respond_to do |format|
        format.turbo_stream { render :invalid, status: :unprocessable_entity }
        format.html { redirect_to project_setup_path(@project), alert: @api_key.errors.full_messages.to_sentence }
      end
    end
end
