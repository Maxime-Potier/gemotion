class CreatePreviews < ActiveRecord::Migration[7.1]
  def change
    create_table :previews do |t|

      t.timestamps
    end
  end
end
