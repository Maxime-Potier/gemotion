require "test_helper"

class VideosControllerTest < ActionDispatch::IntegrationTest
  test "should get start" do
    get start_url
    assert_redirected_to new_user_session_url
  end
end
