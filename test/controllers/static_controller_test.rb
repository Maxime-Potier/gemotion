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
    assert_select "#language_switcher a[href='/fr'][data-locale='fr']", text: "FR"
    assert_select "#language_switcher a[href='/en'][data-locale='en'][aria-current='page']", text: "EN"
    assert_no_match(/translation_missing/, response.body)
  end

  test "language switch preserves the page and marks French as active" do
    get about_url(locale: :fr)

    assert_response :success
    assert_select "#primary_menu", text: /Comment ça marche/
    assert_select "#language_switcher a[href='/fr/about'][data-locale='fr'][aria-current='page']", text: "FR"
    assert_select "#language_switcher a[href='/en/about'][data-locale='en']:not([aria-current])", text: "EN"
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
