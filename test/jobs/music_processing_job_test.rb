require "test_helper"
require "minitest/mock"

class MusicProcessingJobTest < ActiveJob::TestCase
  test "reads custom music from Active Storage when generating its waveform" do
    user = User.create!(
      email: "music-waveform-job-test@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456771"
    )
    video = user.videos.create!(video_type: :solo)
    chapter_type = ChapterType.create!(name: "Music")
    chapter = video.video_chapters.create!(chapter_type:, text: "Waveform")
    chapter.custom_music.attach(
      io: File.open(Rails.root.join("app/assets/musiques/ami-1.mp3")),
      filename: "ami-1.mp3",
      content_type: "audio/mpeg"
    )
    successful_status = Struct.new(:success?).new(true)

    capture_waveform = lambda do |*arguments|
      input_path = arguments.fetch(arguments.index("-i") + 1)
      output_path = arguments.fetch(arguments.index("-o") + 1)

      assert File.exist?(input_path), "expected the Active Storage blob to be available to the worker"
      File.write(output_path, { data: [10, 20, 30] }.to_json)
      ["", "", successful_status]
    end

    Open3.stub(:capture3, capture_waveform) do
      MusicProcessingJob.perform_now("VideoChapter", chapter.id)
    end

    assert_equal({ "data" => [10, 20, 30] }, chapter.reload.waveform)
  end
end
