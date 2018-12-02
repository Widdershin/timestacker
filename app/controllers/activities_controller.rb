class ActivitiesController < ApplicationController
  def index
    render json: current_user.activities.active
  end

  def create
    render json: current_user.activities.active.create!(activity_params)
  end

  def update
    activity = Activity.find(params[:id])

    activity.update!(activity_params)

    render json: activity
  end

  def destroy
    activity = Activity.find(params[:id])

    activity.update!(archived: true)

    render json: activity
  end

  private

  def activity_params
    params.require(:activity).permit(:name, :color)
  end
end
