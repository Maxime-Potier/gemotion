require "test_helper"

class StaticControllerTest < ActionDispatch::IntegrationTest
  test "should get home" do
    get root_url
    assert_response :success
  end

  test "language switch renders English without missing translation markers" do
    get root_url(locale: :en)

    assert_response :success
    assert_select "#primary_menu", text: /Home/
    assert_select "a[href='/fr']", text: "FR"
    assert_select "a[href='/en']", text: "EN"
    assert_no_match(/translation_missing/, response.body)
  end

  test "should get about" do
    get about_url
    assert_response :success
  end

  test "should get pricing" do
    get pricing_url
    assert_response :success
  end

  # test "should get contact" do
  #   get static_contact_url
  #   assert_response :success
  # end

end
