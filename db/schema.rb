# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2024_10_23_074257) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "chapter_types", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "contact_forms", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "contacts", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dedicace_contents", force: :cascade do |t|
    t.bigint "video_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["video_id"], name: "index_dedicace_contents_on_video_id"
  end

  create_table "dedicaces", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "musics", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "previews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "video_chapters", force: :cascade do |t|
    t.bigint "chapter_type_id", null: false
    t.bigint "video_id", null: false
    t.text "text", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "ordered_videos_ids", default: []
    t.json "ordered_images_ids", default: []
    t.index ["chapter_type_id"], name: "index_video_chapters_on_chapter_type_id"
    t.index ["video_id"], name: "index_video_chapters_on_video_id"
  end

  create_table "video_destinataires", force: :cascade do |t|
    t.integer "genre"
    t.integer "age"
    t.string "name"
    t.text "more_info"
    t.bigint "video_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["video_id"], name: "index_video_destinataires_on_video_id"
  end

  create_table "video_musics", force: :cascade do |t|
    t.bigint "music_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_chapter_id", null: false
    t.index ["music_id"], name: "index_video_musics_on_music_id"
    t.index ["video_chapter_id"], name: "index_video_musics_on_video_chapter_id"
  end

  create_table "video_previews", force: :cascade do |t|
    t.bigint "preview_id", null: false
    t.bigint "video_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.index ["preview_id"], name: "index_video_previews_on_preview_id"
    t.index ["video_id"], name: "index_video_previews_on_video_id"
  end

  create_table "videos", force: :cascade do |t|
    t.integer "video_type", null: false
    t.string "stop_at", default: "start", null: false
    t.integer "occasion"
    t.datetime "end_date"
    t.integer "theme"
    t.text "theme_specific_request"
    t.string "token"
    t.text "music_specific_request"
    t.text "dedicace_specific_request"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "music_id"
    t.bigint "dedicace_id"
    t.integer "music_type", default: 0, null: false
    t.index ["dedicace_id"], name: "index_videos_on_dedicace_id"
    t.index ["music_id"], name: "index_videos_on_music_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "dedicace_contents", "videos"
  add_foreign_key "video_chapters", "chapter_types"
  add_foreign_key "video_chapters", "videos"
  add_foreign_key "video_destinataires", "videos"
  add_foreign_key "video_musics", "musics"
  add_foreign_key "video_musics", "video_chapters"
  add_foreign_key "video_previews", "previews"
  add_foreign_key "video_previews", "videos"
  add_foreign_key "videos", "dedicaces"
  add_foreign_key "videos", "musics"
end
