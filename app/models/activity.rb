class Activity < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :color, length: {is: 7}

  scope :archived, -> { where(archived: true) }
  scope :active, -> { where(archived: false) }
end
