require "test_helper"

class VideosControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

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

  test "demo payment is always available and completes the project without a Stripe token" do
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
    assert_select "#payment-form button[type='submit']:not([disabled])", text: "Pay"
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
end
