# frozen_string_literal: true

require "test_helper"
require "cgi"
require "uri"

class PasswordRecoveryTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    @user = User.create!(
      first_name: "Password",
      last_name: "Recovery",
      phone: "+10000000000",
      email: "password-recovery-#{SecureRandom.hex(6)}@example.com",
      password: "old-password",
      password_confirmation: "old-password"
    )
  end

  test "user can request and complete an English password reset" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      post user_password_path(locale: :en), params: { user: { email: @user.email } }
    end

    assert_redirected_to new_user_session_path(locale: :en)

    email = ActionMailer::Base.deliveries.last
    reset_url = reset_url_from(email)
    reset_token = reset_token_from(reset_url)

    assert_includes reset_url, "/en/users/password/edit"
    assert_includes email.body.to_s, "Change my password"

    get reset_url
    assert_response :success
    assert_includes response.body, "Change your password"

    put user_password_path(locale: :en), params: {
      user: {
        reset_password_token: reset_token,
        password: "new-password",
        password_confirmation: "new-password"
      }
    }

    assert_response :redirect
    assert @user.reload.valid_password?("new-password")
    assert_not @user.valid_password?("old-password")
  end

  test "French reset email and link use the requested locale" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      post user_password_path(locale: :fr), params: { user: { email: @user.email } }
    end

    email = ActionMailer::Base.deliveries.last

    assert_equal "Instructions de réinitialisation du mot de passe", email.subject
    assert_includes reset_url_from(email), "/fr/users/password/edit"
    assert_includes email.body.to_s, "Changer mon mot de passe"
  end

  test "signed-in user can change the password with the current password" do
    post user_session_path(locale: :en), params: {
      user: { email: @user.email, password: "old-password" }
    }
    assert_response :redirect

    get edit_user_registration_path(locale: :en)
    assert_response :success
    assert_includes response.body, "Change your password"

    put user_registration_path(locale: :en), params: {
      user: {
        email: @user.email,
        current_password: "old-password",
        password: "changed-password",
        password_confirmation: "changed-password"
      }
    }

    assert_response :redirect
    assert @user.reload.valid_password?("changed-password")
    assert_not @user.valid_password?("old-password")
  end

  private

  def reset_url_from(email)
    CGI.unescapeHTML(email.body.to_s.match(/href="([^"]+reset_password_token=[^"]+)"/)[1])
  end

  def reset_token_from(url)
    Rack::Utils.parse_query(URI.parse(url).query).fetch("reset_password_token")
  end
end
