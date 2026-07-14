require "test_helper"

class VideoTest < ActiveSupport::TestCase
  test "invalidating generated outputs removes stale preview and resets processing" do
    user = User.create!(
      email: "preview-reset@example.test",
      password: "password",
      first_name: "Preview",
      last_name: "Reset",
      phone: "+10000000000"
    )
    video = user.videos.create!(video_type: :solo, concat_status: :completed, processing_progress: 100)
    video.final_video_with_watermark.attach(
      io: StringIO.new("stale preview"),
      filename: "stale-preview.mp4",
      content_type: "video/mp4"
    )

    video.invalidate_generated_outputs!

    assert_predicate video.reload, :pending?
    assert_equal 0, video.processing_progress
    assert_not video.final_video_with_watermark.attached?
  end
end
