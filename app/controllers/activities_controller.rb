class ActivitiesController < ApplicationController
  def index
    render json: current_user.activities.to_json(:methods => :remaining_blocks)
  end

  def create
    render json: current_user.activities.create!(activity_params).to_json(:methods => :remaining_blocks)
  end

  private

  def activity_params
    params.require(:activity).permit(:name, :color, :time_blocks_per_week)
  end
end
