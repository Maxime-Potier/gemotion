require "test_helper"

class VideosControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

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
end
