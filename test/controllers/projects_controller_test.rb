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
    assert_select ".participants-progress-content[style*='width: 100%']"
    assert_select ".video-processing-state-wrapper[style*='justify-content: center']"
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
    dedicace = Dedicace.create!(name: "Chanson", description: "Description française")
    video = user.videos.create!(video_type: :solo, dedicace:)
    sign_in user

    assert_difference("VideoDedicace.count", 1) do
      get creator_manage_dedicace_url(video, locale: :en)
    end

    assert_response :success
    assert_equal dedicace, video.reload.video_dedicace.dedicace
    assert_select ".video-slot", count: 3
    assert_select ".plus-button", count: 3
    assert_select "h1", text: "Add your video part to the final dedication"
    assert_select ".dedication-name", text: "Song"
    assert_select ".p-text-16", text: "A musical final dedication built around a song."
    assert_select "input[type='submit'][value='Save changes']"
    assert_includes response.body, update_video_slot_path(video, locale: :en).to_json
    assert_includes response.body, get_video_slot_status_path(video, locale: :en).to_json
    assert_no_match(%r{http://localhost:5000/videos/}, response.body)
    assert_no_match(/Ajoutez|Pas de vidéo|Vos médias|Thème|Sauvegarder/, response.body)
  end

  test "collaborator final dedication page is localized in English" do
    owner = User.create!(
      email: "dedication-owner@example.com",
      password: "Password123!",
      first_name: "Owner",
      last_name: "User",
      phone: "+33123456803"
    )
    collaborator = User.create!(
      email: "dedication-collaborator@example.com",
      password: "Password123!",
      first_name: "Collaborator",
      last_name: "User",
      phone: "+33123456804"
    )
    dedicace = Dedicace.create!(name: "On danse", description: "Description française")
    video = owner.videos.create!(video_type: :colab, dedicace:)
    Collaboration.create!(
      video:,
      inviting_user: owner,
      invited_user: collaborator,
      invited_email: collaborator.email
    )
    sign_in collaborator

    get collaborator_manage_dedicace_url(video, locale: :en)

    assert_response :success
    assert_select "h1", text: "Add your video part to the final dedication"
    assert_select ".dedication-name", text: "We dance"
    assert_select ".p-text-16", text: "An energetic final dedication where everyone joins the dance."
    assert_select "#videoPreviewText", text: "The view from the front camera opens here"
    assert_select "input[type='submit'][value='Save changes']"
    assert_no_match(/Ajoutez|Pas de vidéo|Vos médias|Thème|Sauvegarder/, response.body)
  end
end
