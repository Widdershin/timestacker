class ActivitiesController < ApplicationController
  def index
    render json: current_user.activities
  end

  def create
    render json: current_user.activities.create!(activity_params)
  end

  def update
    activity = Activity.find(params[:id])

    activity.update!(activity_params)

    render json: activity
  end

  private

  def activity_params
    params.require(:activity).permit(:name, :color)
  end
end
