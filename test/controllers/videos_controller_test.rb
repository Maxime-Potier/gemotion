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
    assert_select "#video-processing-state[data-status-url='#{video_concat_status_path(video, locale: :en)}']"
    assert_select "#video-processing-title", text: "Your video is being prepared"
    assert_select "#video-processing-progress-bar[style='width: 42%']"
    assert_select "#video-processing-progress-value", text: "42%"
    assert_select "video", count: 0
    assert_select "input[type='submit'][value='Save and pay']", count: 0
    assert_includes response.body, "window.location.reload()"

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
    sign_in user

    assert_enqueued_with(job: ContentDedicaceJob, args: [video.id]) do
      get edit_video_url(locale: :en)
    end

    assert_response :success
    assert video.reload.processing?
    assert_equal 0, video.processing_progress
    assert_select "#video-processing-state"
  end
end
