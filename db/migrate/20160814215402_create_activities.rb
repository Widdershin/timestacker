class CreateActivities < ActiveRecord::Migration[5.0]
  def change
    create_table :activities do |t|
      t.text :name
      t.integer :time_blocks_per_week
      t.belongs_to :user

      t.timestamps
    end
  end
end
