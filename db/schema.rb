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

ActiveRecord::Schema[7.1].define(version: 2025_04_01_110536) do
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

  create_table "collaborations", force: :cascade do |t|
    t.bigint "video_id", null: false
    t.bigint "inviting_user_id", null: false
    t.bigint "invited_user_id"
    t.string "invited_email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_user_id"], name: "index_collaborations_on_invited_user_id"
    t.index ["inviting_user_id"], name: "index_collaborations_on_inviting_user_id"
    t.index ["video_id"], name: "index_collaborations_on_video_id"
  end

  create_table "collaborator_chapters", force: :cascade do |t|
    t.string "text", null: false
    t.string "videos_order", default: ""
    t.string "photos_order", default: ""
    t.json "ordered_videos_ids", default: []
    t.json "ordered_images_ids", default: []
    t.string "slide_color"
    t.string "text_family"
    t.string "text_style"
    t.integer "text_size"
    t.integer "order"
    t.bigint "chapter_type_id", null: false
    t.bigint "video_id", null: false
    t.bigint "collaboration_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "approved_by_creator", default: false, null: false
    t.json "waveform"
    t.index ["chapter_type_id"], name: "index_collaborator_chapters_on_chapter_type_id"
    t.index ["collaboration_id"], name: "index_collaborator_chapters_on_collaboration_id"
    t.index ["video_id"], name: "index_collaborator_chapters_on_video_id"
  end

  create_table "collaborator_dedicaces", force: :cascade do |t|
    t.bigint "dedicace_id", null: false
    t.bigint "video_id", null: false
    t.bigint "collaboration_id", null: false
    t.string "car_position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "approved_by_creator", default: false, null: false
    t.index ["collaboration_id"], name: "index_collaborator_dedicaces_on_collaboration_id"
    t.index ["dedicace_id"], name: "index_collaborator_dedicaces_on_dedicace_id"
    t.index ["video_id"], name: "index_collaborator_dedicaces_on_video_id"
  end

  create_table "collaborator_musics", force: :cascade do |t|
    t.bigint "music_id", null: false
    t.bigint "collaborator_chapter_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collaborator_chapter_id"], name: "index_collaborator_musics_on_collaborator_chapter_id"
    t.index ["music_id"], name: "index_collaborator_musics_on_music_id"
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
    t.string "car_position"
  end

  create_table "musics", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "waveform"
  end

  create_table "previews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "text"
    t.string "text_position"
    t.float "start_time"
    t.float "duration"
    t.string "font_type"
    t.string "font_style"
    t.integer "font_size"
    t.string "animation"
    t.string "text_color"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "phone"
    t.string "first_name"
    t.string "last_name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "video_chapters", force: :cascade do |t|
    t.bigint "chapter_type_id", null: false
    t.bigint "video_id", null: false
    t.text "text", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "ordered_videos_ids", default: []
    t.json "ordered_images_ids", default: []
    t.string "slide_color"
    t.string "text_family"
    t.string "text_style"
    t.integer "text_size"
    t.integer "order"
    t.string "videos_order", default: ""
    t.string "photos_order", default: ""
    t.json "waveform"
    t.index ["chapter_type_id"], name: "index_video_chapters_on_chapter_type_id"
    t.index ["video_id"], name: "index_video_chapters_on_video_id"
  end

  create_table "video_dedicaces", force: :cascade do |t|
    t.bigint "dedicace_id", null: false
    t.bigint "video_id", null: false
    t.string "car_position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dedicace_id"], name: "index_video_dedicaces_on_dedicace_id"
    t.index ["video_id"], name: "index_video_dedicaces_on_video_id"
  end

  create_table "video_destinataires", force: :cascade do |t|
    t.integer "genre"
    t.integer "age"
    t.string "name"
    t.text "more_info"
    t.bigint "video_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "passions_and_hobbies"
    t.text "personality_description"
    t.text "favorite_quotes"
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
    t.bigint "user_id", null: false
    t.integer "concat_status", default: 0, null: false
    t.integer "project_status", default: 0, null: false
    t.string "title"
    t.string "description"
    t.boolean "paid"
    t.text "previews_order", default: [], array: true
    t.text "special_request_music"
    t.text "special_request_dedicace"
    t.integer "introduction_video", default: 0, null: false
    t.index ["dedicace_id"], name: "index_videos_on_dedicace_id"
    t.index ["music_id"], name: "index_videos_on_music_id"
    t.index ["user_id"], name: "index_videos_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "collaborations", "users", column: "invited_user_id"
  add_foreign_key "collaborations", "users", column: "inviting_user_id"
  add_foreign_key "collaborations", "videos"
  add_foreign_key "collaborator_chapters", "chapter_types"
  add_foreign_key "collaborator_chapters", "collaborations"
  add_foreign_key "collaborator_chapters", "videos"
  add_foreign_key "collaborator_dedicaces", "collaborations"
  add_foreign_key "collaborator_dedicaces", "dedicaces"
  add_foreign_key "collaborator_dedicaces", "videos"
  add_foreign_key "collaborator_musics", "collaborator_chapters"
  add_foreign_key "collaborator_musics", "musics"
  add_foreign_key "dedicace_contents", "videos"
  add_foreign_key "video_chapters", "chapter_types"
  add_foreign_key "video_chapters", "videos"
  add_foreign_key "video_dedicaces", "dedicaces"
  add_foreign_key "video_dedicaces", "videos"
  add_foreign_key "video_destinataires", "videos"
  add_foreign_key "video_musics", "musics"
  add_foreign_key "video_musics", "video_chapters"
  add_foreign_key "video_previews", "previews"
  add_foreign_key "video_previews", "videos"
  add_foreign_key "videos", "dedicaces"
  add_foreign_key "videos", "musics"
  add_foreign_key "videos", "users"
end
