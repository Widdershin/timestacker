class DeleteBlocks < ActiveRecord::Migration[5.2]
  def change
    drop_table :blocks
    drop_table :completed_blocks
    remove_column :activities, :time_blocks_per_week
  end
end
