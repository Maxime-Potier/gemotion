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

    post dedicace_post_url(locale: :fr), params: { special_request_dedicace: "" }

    assert_response :unprocessable_entity
    assert_select ".alert", text: /Vous devez séléctionnez une dedicace/
  end
end
