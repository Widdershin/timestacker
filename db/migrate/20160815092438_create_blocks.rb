class CreateBlocks < ActiveRecord::Migration[5.0]
  def change
    create_table :blocks do |t|
      t.boolean :complete
      t.belongs_to :activity

      t.timestamps
    end
  end
end
