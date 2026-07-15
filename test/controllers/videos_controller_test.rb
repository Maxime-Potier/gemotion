require "test_helper"

class VideosControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  test "deadline calendar renders its initial date in a browser-safe ISO format" do
    user = User.create!(
      email: "deadline-calendar-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456790"
    )
    user.videos.create!(
      video_type: :solo,
      stop_at: "content",
      end_date: Time.zone.local(2026, 7, 22, 14, 30)
    )
    sign_in user

    get deadline_url(locale: :en)

    assert_response :success
    assert_select "[data-controller='custom-calendar'][data-custom-calendar-locale-value='en']"
    assert_select "input[name='end_date'][value='2026-07-22']"
    assert_no_match(/2026-07-22 14:30:00/, response.body)
  end

  test "should get start" do
    get start_url
    assert_redirected_to new_user_session_url
  end

  test "dedicace validation renders the step instead of raising a missing template error" do
    user = User.create!(
      email: "dedicace-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456789"
    )
    user.videos.create!(video_type: :solo, stop_at: "music")
    sign_in user

    post dedicace_post_url(locale: :en), params: { special_request_dedicace: "" }

    assert_response :unprocessable_entity
    assert_select ".alert", text: "Please select a dedication."
  end

  test "recipient validation alert uses the requested locale" do
    user = User.create!(
      email: "recipient-validation-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456779"
    )
    user.videos.create!(video_type: :solo, stop_at: "occasion")
    sign_in user

    post info_destinataire_post_url(locale: :en), params: {
      age_destinataire: "10",
      name_destinataire: "",
      more_info_destinataire: "Some details",
      passions_and_hobbies: "Music",
      personality_description: "Kind",
      favorite_quotes: "A quote"
    }

    assert_response :unprocessable_entity
    assert_select ".alert", text: "Please fill in all required fields."
    assert_no_match(/Veuillez remplir/, response.body)
    assert_select "input[name='age_destinataire'][value='10']"
    assert_select "input[name='name_destinataire'][value='']"
    assert_select "textarea[name='more_info_destinataire']", text: "Some details"
    assert_select "textarea[name='passions_and_hobbies']", text: "Music"
    assert_select "textarea[name='personality_description']", text: "Kind"
    assert_select "textarea[name='favorite_quotes']", text: "A quote"
  end

  test "final dedication step requires at least one processed recording" do
    user = User.create!(
      email: "final-dedicace-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456780"
    )
    dedicace = Dedicace.create!(name: "Carpool")
    video = user.videos.create!(video_type: :colab, stop_at: "content", dedicace: dedicace)
    sign_in user

    patch dedicace_de_fin_post_url(video, locale: :en)

    assert_response :unprocessable_entity
    assert_select ".alert", text: "Please record and process at least one dedication video before continuing."
    assert_select "#dedicace-recording-form[data-turbo='false']"
    assert_select ".video-slot[data-slot-number]", count: 3
    assert_select "#videoPreview.camera-preview-video"
    assert_includes response.body, "object-fit: contain"
    assert_includes response.body, 'width: { ideal: 1280 }'
    assert_includes response.body, 'height: { ideal: 720 }'
    assert_no_match(/aspectRatio:\s*\{\s*ideal:\s*0\.5625\s*\}/, response.body)
    assert_includes response.body, "stream.getAudioTracks()"
    assert_includes response.body, "videoPreview.removeAttribute('muted')"
    assert_includes response.body, "videoPreview.defaultMuted = false"
    assert_includes response.body, "videoPreview.volume = 1"
    assert_includes response.body, 'document.addEventListener("turbo:load", initializeDedicaceRecording)'
    assert_equal dedicace, video.reload.video_dedicace.dedicace
  end

  test "recorded video is accepted and linked to the selected dedication" do
    user = User.create!(
      email: "recording-upload-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456781"
    )
    dedicace = Dedicace.create!(name: "Carpool")
    video = user.videos.create!(video_type: :colab, stop_at: "content", dedicace: dedicace)
    upload = Rack::Test::UploadedFile.new(Rails.root.join("app/assets/videos/about.mp4"), "video/mp4")
    sign_in user

    patch update_video_slot_url(video, locale: :en), params: { slot_number: 1, video_file: upload }

    assert_response :success
    assert_equal "processing", response.parsed_body["status"]
    assert_equal dedicace, video.reload.video_dedicace.dedicace
    assert_equal 1, video.video_dedicace.video_dedicace_slots.find_by!(slot: 1).slot
  ensure
    Dir[Rails.root.join("tmp/temp_video_*_1_*.webm")].each { |path| File.delete(path) }
  end

  test "demo payment completes the project when the bypass is explicitly enabled" do
    previous_bypass = ENV["PAYMENT_BYPASS_ENABLED"]
    ENV["PAYMENT_BYPASS_ENABLED"] = "true"
    user = User.create!(
      email: "demo-payment-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456782"
    )
    video = user.videos.create!(video_type: :solo, stop_at: "content_dedicace")
    sign_in user

    get payment_url(locale: :en)

    assert_response :success
    assert_select "#payment-form button[type='submit']:not([disabled])", text: /Pay €/
    assert_select "[role='status']", text: /Temporary demo mode/

    post payment_post_url(locale: :en)

    assert_redirected_to participants_progress_url(locale: :en, video_id: video.id)
    assert video.reload.paid?
    assert video.finished?

    follow_redirect!
    assert_response :success
    assert_select ".hello-block", text: /Hello, Test User!/
    assert_select ".choose-prof-block", text: /Profile details.*Current projects.*Log out/m
    assert_select "button", text: "Change deadline"
    assert_select "button", text: "Close project"
    assert_select "a", text: "Manage chapters"
    assert_no_match(/Modifier la date limite|Clôturer le projet|Gérer les chapitres/, response.body)
  ensure
    ENV["PAYMENT_BYPASS_ENABLED"] = previous_bypass
  end

  test "payment page shows the secure Stripe card form by default" do
    previous_bypass = ENV["PAYMENT_BYPASS_ENABLED"]
    ENV["PAYMENT_BYPASS_ENABLED"] = "false"
    user = User.create!(
      email: "stripe-payment-form-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456784"
    )
    user.videos.create!(video_type: :solo, stop_at: "content_dedicace")
    sign_in user

    get payment_url(locale: :en)

    assert_response :success
    assert_select "#payment-form[data-controller='payment']"
    assert_select "#card-element[data-payment-target='cardElement']"
    assert_select "#payment-form button[type='submit'][disabled]", text: /Pay €/
    assert_select "[role='status']", count: 0
  ensure
    ENV["PAYMENT_BYPASS_ENABLED"] = previous_bypass
  end

  test "deleting an introduction preview keeps the other previews" do
    user = User.create!(
      email: "preview-delete-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456776"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "photo_intro",
      previews_order: %w[first.jpg second.jpg third.jpg]
    )
    previews = %w[first.jpg second.jpg third.jpg].each_with_index.map do |filename, index|
      preview = Preview.create!
      preview.image.attach(io: StringIO.new("image-#{index}"), filename:, content_type: "image/jpeg")
      video.video_previews.create!(preview:, order: index)
      preview
    end
    sign_in user

    assert_difference("video.reload.video_previews.count", -1) do
      delete drop_preview_url(previews.second, locale: :en, video_id: video.id), as: :json
    end

    assert_response :success
    assert_equal [previews.first.id, previews.third.id], video.reload.previews.order(:id).pluck(:id)
    assert_equal %w[first.jpg third.jpg], video.previews_order
    assert_not Preview.exists?(previews.second.id)
  end

  test "deleting a shared introduction preview only removes it from the selected video" do
    user = User.create!(
      email: "shared-preview-delete-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456775"
    )
    video = user.videos.create!(video_type: :solo, stop_at: "photo_intro", previews_order: ["shared.jpg"])
    other_video = user.videos.create!(video_type: :solo, stop_at: "photo_intro", previews_order: ["shared.jpg"])
    preview = Preview.create!
    preview.image.attach(io: StringIO.new("shared-image"), filename: "shared.jpg", content_type: "image/jpeg")
    video.video_previews.create!(preview:, order: 0)
    other_video.video_previews.create!(preview:, order: 0)
    sign_in user

    delete drop_preview_url(preview, locale: :en, video_id: video.id), as: :json

    assert_response :success
    assert_not video.reload.previews.exists?(preview.id)
    assert other_video.reload.previews.exists?(preview.id)
    assert Preview.exists?(preview.id)
  end

  test "edit video shows processing state and polls until the preview is ready" do
    user = User.create!(
      email: "processing-preview-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456783"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "deadline",
      concat_status: :processing,
      processing_progress: 42
    )
    sign_in user

    get edit_video_url(locale: :en)

    assert_response :success
    assert_select "#video-processing-state[data-controller='video-processing-progress']"
    assert_select "#video-processing-state[data-video-processing-progress-status-url-value='#{video_concat_status_path(video, locale: :en)}']"
    assert_select "[data-video-processing-progress-target='title']", text: "Your video is being prepared"
    assert_select "[data-video-processing-progress-target='bar'][style='width: 42%']"
    assert_select "[data-video-processing-progress-target='value']", text: "42%"
    assert_select "video", count: 0
    assert_select "input[type='submit'][value='Save and pay']", count: 0

    get video_concat_status_url(video, locale: :en)

    assert_response :success
    assert_equal "processing", response.parsed_body["concat_status"]
    assert_equal 42, response.parsed_body["processing_progress"]
  end

  test "edit video starts preview generation when the video is pending" do
    user = User.create!(
      email: "pending-preview-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456784"
    )
    video = user.videos.create!(video_type: :solo, stop_at: "deadline", concat_status: :pending)
    music = Music.create!(name: "Pending preview default")
    music.music.attach(
      io: File.open(Rails.root.join("app/assets/musiques/voyage-1.mp3")),
      filename: "voyage-1.mp3",
      content_type: "audio/mpeg"
    )
    sign_in user

    assert_enqueued_with(job: ContentDedicaceJob, args: [video.id]) do
      get edit_video_url(locale: :en)
    end

    assert_response :success
    assert video.reload.processing?
    assert_equal 0, video.processing_progress
    assert_select "#video-processing-state"
  end

  test "saving an unchanged video preserves the completed preview" do
    user = User.create!(
      email: "unchanged-preview-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456788"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "deadline",
      concat_status: :completed,
      processing_progress: 100
    )
    chapter_type = ChapterType.create!(name: "Passions")
    chapter = video.video_chapters.create!(chapter_type:, text: "Existing text", order: 1)
    video.final_video_with_watermark.attach(
      io: StringIO.new("completed preview"),
      filename: "preview.mp4",
      content_type: "video/mp4"
    )
    preview_blob_id = video.final_video_with_watermark.blob.id
    sign_in user

    assert_no_enqueued_jobs only: ContentDedicaceJob do
      post edit_video_post_url(locale: :en), params: {
        chapter_order: "",
        chapters: {
          chapter.id.to_s => {
            text: chapter.text,
            videos_order: "",
            videos: [""],
            photos_order: "",
            photos: [""]
          }
        }
      }
    end

    assert_redirected_to skip_edit_video_url(locale: :en)
    assert video.reload.completed?
    assert_equal 100, video.processing_progress
    assert_equal preview_blob_id, video.final_video_with_watermark.blob.id

    assert_no_enqueued_jobs only: ContentDedicaceJob do
      follow_redirect!
      assert_redirected_to content_dedicace_url(locale: :en)
      follow_redirect!
    end
    assert_response :success
    assert_select "video source[src]"
  end

  test "saving a changed video invalidates the completed preview" do
    user = User.create!(
      email: "changed-preview-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456789"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "deadline",
      concat_status: :completed,
      processing_progress: 100
    )
    chapter_type = ChapterType.create!(name: "Challenges")
    chapter = video.video_chapters.create!(chapter_type:, text: "Old text", order: 1)
    video.final_video_with_watermark.attach(
      io: StringIO.new("stale preview"),
      filename: "preview.mp4",
      content_type: "video/mp4"
    )
    sign_in user

    post edit_video_post_url(locale: :en), params: {
      chapter_order: chapter.id.to_s,
      chapters: {
        chapter.id.to_s => {
          text: "New text",
          videos_order: "",
          videos: [""],
          photos_order: "",
          photos: [""]
        }
      }
    }

    assert_redirected_to skip_edit_video_url(locale: :en)
    assert_equal "New text", chapter.reload.text
    assert video.reload.pending?
    assert_equal 0, video.processing_progress
    assert_not video.final_video_with_watermark.attached?
  end

  test "only an explicit post request refreshes a completed preview" do
    user = User.create!(
      email: "manual-preview-refresh-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456790"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "edit_video",
      concat_status: :completed,
      processing_progress: 100
    )
    music = Music.create!(name: "Manual refresh soundtrack")
    music.music.attach(
      io: File.open(Rails.root.join("app/assets/musiques/voyage-1.mp3")),
      filename: "voyage-1.mp3",
      content_type: "audio/mpeg"
    )
    video.update!(music:)
    video.final_video_with_watermark.attach(
      io: StringIO.new("completed preview"),
      filename: "preview.mp4",
      content_type: "video/mp4"
    )
    sign_in user

    assert_no_enqueued_jobs only: ContentDedicaceJob do
      get content_dedicace_url(locale: :en, refresh: true)
    end
    assert_response :success
    assert video.reload.completed?
    assert video.final_video_with_watermark.attached?
    assert_select "form[action='#{refresh_content_dedicace_path(locale: :en)}'][method='post'] button",
                  text: "Refresh video"

    assert_enqueued_with(job: ContentDedicaceJob, args: [video.id]) do
      post refresh_content_dedicace_url(locale: :en)
    end
    assert_redirected_to content_dedicace_url(locale: :en)
    assert video.reload.processing?
    assert_equal 0, video.processing_progress
    assert_not video.final_video_with_watermark.attached?
  end

  test "music step assigns an available track when the optional selection is empty" do
    user = User.create!(
      email: "optional-music-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456785"
    )
    video = user.videos.create!(video_type: :solo, stop_at: "select_chapters")
    music = Music.create!(name: "Automatic soundtrack")
    music.music.attach(
      io: File.open(Rails.root.join("app/assets/musiques/voyage-1.mp3")),
      filename: "voyage-1.mp3",
      content_type: "audio/mpeg"
    )
    sign_in user

    get music_url(locale: :en)

    assert_response :success
    assert_select "[data-controller='audio-visualizer'][data-audio-src*='disposition=inline']"

    post music_post_url(locale: :en)

    assert_redirected_to dedicace_url(locale: :en)
    assert video.reload.music.music.attached?
    assert_equal "music", video.stop_at
  end

  test "chapter music step assigns an available track when optional chapter selections are empty" do
    user = User.create!(
      email: "optional-chapter-music-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456784"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "select_chapters",
      music_type: :by_chapters
    )
    chapter_type = ChapterType.create!(name: "Memories")
    chapter = video.video_chapters.create!(chapter_type:, text: "Our memories")
    music = Music.create!(name: "Automatic chapter soundtrack")
    music.music.attach(
      io: File.open(Rails.root.join("app/assets/musiques/voyage-1.mp3")),
      filename: "voyage-1.mp3",
      content_type: "audio/mpeg"
    )
    sign_in user

    post music_post_url(locale: :en), params: { "music_#{chapter.id}" => "" }

    assert_redirected_to dedicace_url(locale: :en)
    assert_equal music, chapter.reload.video_music.music
    assert_equal "music", video.reload.stop_at
  end

  test "invalid chapter music selection uses the requested locale" do
    user = User.create!(
      email: "invalid-chapter-music-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456783"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "select_chapters",
      music_type: :by_chapters
    )
    chapter_type = ChapterType.create!(name: "Memories")
    chapter = video.video_chapters.create!(chapter_type:, text: "Our memories")
    sign_in user

    post music_post_url(locale: :en), params: { "music_#{chapter.id}" => "999999" }

    assert_response :unprocessable_entity
    assert_select ".alert", text: "The selected music for chapter #{chapter.id} was not found."
    assert_no_match(/Musique non trouvée/, response.body)
  end

  test "chapter checkboxes have a visible clickable label" do
    user = User.create!(
      email: "chapter-selection-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456786"
    )
    user.videos.create!(video_type: :solo, stop_at: "photo_intro")
    chapter_type = ChapterType.create!(name: "Journey")
    sign_in user

    get select_chapters_url(locale: :en)

    assert_response :success
    assert_select "input#chapter_select_#{chapter_type.id}[type='checkbox']"
    assert_select "label[for='chapter_select_#{chapter_type.id}']", text: "Select chapter"
  end

  test "selected chapter without text shows validation instead of raising an error" do
    user = User.create!(
      email: "chapter-text-validation-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456775"
    )
    video = user.videos.create!(video_type: :solo, stop_at: "photo_intro")
    chapter_type = ChapterType.create!(name: "Life story")
    sign_in user

    assert_no_difference("VideoChapter.count") do
      post select_chapters_post_url(locale: :en), params: {
        chapters: {
          chapter_type.id.to_s => {
            select: "true",
            text: "",
            slide_color: "white",
            text_family: "Poppins",
            text_style: "Normal",
            text_size: "12"
          }
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select ".alert", text: "Enter text for every selected chapter."
    assert_select "input#chapter_select_#{chapter_type.id}[checked='checked']"
    assert_select "input[name='chapters[#{chapter_type.id}][text]'][value='']"
    assert_equal "photo_intro", video.reload.stop_at
  end

  test "chapter content can remove one existing attachment without removing the others" do
    user = User.create!(
      email: "chapter-attachment-delete-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456774"
    )
    video = user.videos.create!(
      video_type: :solo,
      stop_at: "share",
      concat_status: :completed,
      processing_progress: 100
    )
    chapter_type = ChapterType.create!(name: "Memories")
    chapter = video.video_chapters.create!(chapter_type:, text: "Our memories")
    chapter.photos.attach([
      { io: StringIO.new("first photo"), filename: "first.jpg", content_type: "image/jpeg" },
      { io: StringIO.new("second photo"), filename: "second.jpg", content_type: "image/jpeg" }
    ])
    chapter.videos.attach(
      io: StringIO.new("chapter video"), filename: "clip.mp4", content_type: "video/mp4"
    )
    chapter.update!(photos_order: "first.jpg,second.jpg", videos_order: "clip.mp4")
    video.final_video_with_watermark.attach(
      io: StringIO.new("completed preview"), filename: "preview.mp4", content_type: "video/mp4"
    )
    first_photo = chapter.photos.attachments.find_by!(blob: chapter.photos.blobs.find_by!(filename: "first.jpg"))
    sign_in user

    get content_url(locale: :en)

    assert_response :success
    assert_select "button.chapter-attachment-remove[data-url='#{purge_chapter_attachment_path(first_photo.id, locale: :en)}']"
    assert_select "button.chapter-attachment-remove", count: 3

    assert_difference("chapter.reload.photos.count", -1) do
      delete purge_chapter_attachment_url(first_photo, locale: :en), as: :json
    end

    assert_response :success
    assert_equal ["second.jpg"], chapter.reload.photos.map { |photo| photo.filename.to_s }
    assert_equal ["clip.mp4"], chapter.videos.map { |chapter_video| chapter_video.filename.to_s }
    assert_equal "second.jpg", chapter.photos_order
    assert video.reload.pending?
    assert_equal 0, video.processing_progress
    assert_not video.final_video_with_watermark.attached?
  end

  test "photo upload validation message uses the requested locale" do
    user = User.create!(
      email: "photo-upload-locale-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456785"
    )
    user.videos.create!(video_type: :solo, stop_at: "introduction")
    sign_in user

    get photo_intro_url(locale: :en)

    assert_response :success
    assert_includes response.body, "Please upload at least one image."
    assert_no_match(/Veuillez télécharger au moins une image/, response.body)
  end

  test "solo share page is fully translated in English" do
    user = User.create!(
      email: "share-translation-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456787"
    )
    user.videos.create!(video_type: :solo, stop_at: "dedicace", token: SecureRandom.urlsafe_base64(20))
    sign_in user

    get share_url(locale: :en)

    assert_response :success
    assert_select "h1", text: "Invite friends to collaborate on your project!"
    assert_includes response.body, "If you invite friends, they can add content"
    assert_no_match(/translation missing/, response.body)
  end

  test "share invitation confirmation uses the requested locale" do
    user = User.create!(
      email: "share-invitation-locale-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456786"
    )
    user.videos.create!(video_type: :solo, stop_at: "dedicace", token: SecureRandom.urlsafe_base64(20))
    sign_in user

    post share_post_url(locale: :en), params: { email: "invited-person@example.com" }

    assert_redirected_to share_url(locale: :en)
    follow_redirect!
    assert_select ".notice", text: "Invitation sent."
    assert_no_match(/Invitation envoyée?\./, response.body)
  end
end
