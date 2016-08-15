class BlocksController < ApplicationController
  def create
    render json: Block.create(params.require(:block).permit(:activity_id, :complete).merge(:created_date => Date.today))
  end
end
