class ActivitiesController < ApplicationController
  def index
    render json: current_user.activities
  end
end
