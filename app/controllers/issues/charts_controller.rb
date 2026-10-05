# The occurrences chart frame: the 24h / 7d / 30d switch and live reloads.
class Issues::ChartsController < ApplicationController
  include IssueScoped

  def show
    @chart = IssueChart.new(@issue, params[:period])
  end
end
