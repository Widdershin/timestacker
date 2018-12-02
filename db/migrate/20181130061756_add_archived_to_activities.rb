class AddArchivedToActivities < ActiveRecord::Migration[5.2]
  def change
    add_column :activities, :archived, :boolean, default: :false, null: false
  end
end
