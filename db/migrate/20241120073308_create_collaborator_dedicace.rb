class CreateCollaboratorDedicace < ActiveRecord::Migration[7.1]
  def change
    create_table :collaborator_dedicaces do |t|
      t.references :dedicace, null: false, foreign_key: true
      t.references :video, null: false, foreign_key: true
      t.references :collaboration, null: false, foreign_key: true # Reference to collaboration for collaborator user
      t.string :car_position

      t.timestamps
    end
  end
end