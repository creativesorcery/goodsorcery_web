# Shows one full ingest key in its token frame. The response is never cached:
# ApplicationController already sends Cache-Control: no-store, this controller
# repeats it explicitly, and nothing here touches Rails.cache or fragments.
class Projects::ApiKeys::RevealsController < ApplicationController
  include ProjectScoped

  def show
    @api_key = @project.api_keys.find(params[:api_key_id])
    no_store
    render layout: false
  end
end
