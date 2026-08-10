require "test_helper"

class VideoChapterTest < ActiveSupport::TestCase
  test "accepts up to twenty photos and videos" do
    user = User.create!(
      email: "chapter-media-limit@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456770"
    )
    video = user.videos.create!(video_type: :solo)
    chapter_type = ChapterType.create!(name: "Media limit")
    chapter = video.video_chapters.build(chapter_type:, text: "Twenty files")

    ChapterSharedBehavior::MEDIA_LIMIT.times do |index|
      chapter.photos.attach(
        io: StringIO.new("photo #{index}"),
        filename: "photo-#{index}.jpg",
        content_type: "image/jpeg"
      )
      chapter.videos.attach(
        io: StringIO.new("video #{index}"),
        filename: "video-#{index}.mp4",
        content_type: "video/mp4"
      )
    end

    assert chapter.valid?
  end

  test "rejects more than twenty photos" do
    user = User.create!(
      email: "chapter-media-over-limit@example.com",
      password: "Password123!",
      first_name: "Test",
      last_name: "User",
      phone: "+33123456771"
    )
    video = user.videos.create!(video_type: :solo)
    chapter_type = ChapterType.create!(name: "Media over limit")
    chapter = video.video_chapters.build(chapter_type:, text: "Too many files")

    (ChapterSharedBehavior::MEDIA_LIMIT + 1).times do |index|
      chapter.photos.attach(
        io: StringIO.new("photo #{index}"),
        filename: "photo-#{index}.jpg",
        content_type: "image/jpeg"
      )
    end

    assert_not chapter.valid?
    assert_includes chapter.errors[:photos], "cannot exceed 20 files"
  end
end
