class Activity < ApplicationRecord
  belongs_to :user
  has_many :blocks

  def remaining_blocks
    time_blocks_per_week - blocks.where({:complete => true, :created_date => Date.today}).count
  end
end
