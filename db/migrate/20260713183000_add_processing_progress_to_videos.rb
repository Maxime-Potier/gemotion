class AddProcessingProgressToVideos < ActiveRecord::Migration[7.1]
  def change
    add_column :videos, :processing_progress, :integer, default: 0, null: false
  end
end
