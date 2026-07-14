# frozen_string_literal: true

# Receives and verifies asynchronous payment events from Stripe.
class StripeWebhooksController < ActionController::API
  def create
    event = Stripe::Webhook.construct_event(
      request.body.read,
      request.headers["Stripe-Signature"],
      ENV.fetch("STRIPE_WEBHOOK_SECRET")
    )

    handle_charge_succeeded(event.data.object) if event.type == "charge.succeeded"

    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end

  private

  def handle_charge_succeeded(charge)
    return unless charge.paid && charge.status == "succeeded"

    video_id = charge.metadata["video_id"]
    return log_missing_video_id(charge) if video_id.blank?

    video = Video.find_by(id: video_id)
    return log_missing_video(charge, video_id) unless video
    return if video.paid? && video.finished?

    video.update!(paid: true, project_status: :finished)
  end

  def log_missing_video_id(charge)
    Rails.logger.warn("Stripe charge #{charge.id} has no video_id metadata")
  end

  def log_missing_video(charge, video_id)
    Rails.logger.warn("Stripe charge #{charge.id} references missing video #{video_id}")
  end
end
