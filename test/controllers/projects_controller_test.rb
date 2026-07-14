require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "participants progress shows staged render progress" do
    user = User.create!(
      email: "project-progress-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456801"
    )
    video = user.videos.create!(
      video_type: :solo,
      concat_status: :processing,
      processing_progress: 42
    )
    sign_in user

    get participants_progress_url(locale: :en, video_id: video.id)

    assert_response :success
    assert_select "#video-processing-state[data-controller='video-processing-progress']"
    assert_select "#video-processing-state[data-video-processing-progress-status-url-value='#{video_concat_status_path(video, locale: :en)}']"
    assert_select "[data-video-processing-progress-target='bar'][style='width: 42%']"
    assert_select "[data-video-processing-progress-target='value']", text: "42%"
  end

  test "creator can manage a final dedication before recording any slots" do
    user = User.create!(
      email: "manage-dedication-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456802"
    )
    dedicace = Dedicace.create!(name: "Carpool")
    video = user.videos.create!(video_type: :solo, dedicace:)
    sign_in user

    assert_difference("VideoDedicace.count", 1) do
      get creator_manage_dedicace_url(video, locale: :en)
    end

    assert_response :success
    assert_equal dedicace, video.reload.video_dedicace.dedicace
    assert_select ".video-slot", count: 3
    assert_select ".plus-button", count: 3
  end
end
