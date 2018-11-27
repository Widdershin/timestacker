class Activity < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :color, length: {is: 7}
end
