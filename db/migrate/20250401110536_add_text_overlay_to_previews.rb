class AddTextOverlayToPreviews < ActiveRecord::Migration[7.1]
  def change
    add_column :previews, :text, :string
    add_column :previews, :text_position, :string
    add_column :previews, :start_time, :float
    add_column :previews, :duration, :float
    add_column :previews, :font_type, :string
    add_column :previews, :font_style, :string
    add_column :previews, :font_size, :integer
    add_column :previews, :animation, :string
    add_column :previews, :text_color, :string
  end
end
