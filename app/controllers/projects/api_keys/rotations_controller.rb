# Replaces an ingest key's token. The old token stops working immediately:
# ApiKey#rotate deletes its cached credential. The response shows the new
# token once, so it is sent with Cache-Control: no-store.
class Projects::ApiKeys::RotationsController < ApplicationController
  include ProjectScoped
  include VerifiedEmailRequired

  require_verified_email

  def create
    @api_key = @project.api_keys.find(params[:api_key_id]).rotate
    no_store

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to project_setup_path(@project), notice: "Rotated the #{@api_key.environment} key." }
    end
  end
end
