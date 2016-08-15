class AddCreatedDateToBlocks < ActiveRecord::Migration[5.0]
  def change
    add_column :blocks, :created_date, :date
  end
end
