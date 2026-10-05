# Live frame: "Across all projects, last hour" on the overview.
class RecentIssuesController < ApplicationController
  def show
    @feed = RecentFeed.new(Current.account)
    render layout: false
  end
end
