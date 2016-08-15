class ActivitiesController < ApplicationController
  def index
    render json: current_user.activities.to_json(:methods => :remaining_blocks)
  end
end
