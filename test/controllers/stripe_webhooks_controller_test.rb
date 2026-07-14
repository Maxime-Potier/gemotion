# frozen_string_literal: true

require "test_helper"
require "openssl"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "whsec_test_secret"

  setup do
    @previous_webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]
    ENV["STRIPE_WEBHOOK_SECRET"] = WEBHOOK_SECRET

    user = User.create!(
      email: "stripe-webhook@example.com",
      password: "password123",
      first_name: "Stripe",
      last_name: "Webhook",
      phone: "+10000000000"
    )
    @video = Video.create!(user:, video_type: :solo)
  end

  teardown do
    ENV["STRIPE_WEBHOOK_SECRET"] = @previous_webhook_secret
  end

  test "marks the referenced video as paid for a successful charge" do
    post_webhook(event_payload("charge.succeeded", paid: true, status: "succeeded"))

    assert_response :success
    assert @video.reload.paid?
    assert @video.finished?
  end

  test "rejects an invalid signature" do
    payload = event_payload("charge.succeeded", paid: true, status: "succeeded")

    post stripe_webhook_url,
         params: payload,
         headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "invalid" }

    assert_response :bad_request
    assert_not @video.reload.paid?
  end

  test "acknowledges unrelated events without changing the video" do
    post_webhook(event_payload("charge.failed", paid: false, status: "failed"))

    assert_response :success
    assert_not @video.reload.paid?
  end

  private

  def event_payload(type, paid:, status:)
    {
      id: "evt_test_#{SecureRandom.hex(4)}",
      object: "event",
      type:,
      data: { object: charge_payload(paid:, status:) }
    }.to_json
  end

  def charge_payload(paid:, status:)
    {
      id: "ch_test_#{SecureRandom.hex(4)}",
      object: "charge",
      paid:,
      status:,
      metadata: { video_id: @video.id.to_s }
    }
  end

  def post_webhook(payload)
    timestamp = Time.current.to_i
    signature = OpenSSL::HMAC.hexdigest("SHA256", WEBHOOK_SECRET, "#{timestamp}.#{payload}")

    post stripe_webhook_url,
         params: payload,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
         }
  end
end
