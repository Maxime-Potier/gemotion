require "open3"
require "shellwords"
class VideoProcessingJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: false

  def perform(id, klass)
    record_class = klass.constantize
    video_dedicace = record_class.find(id)
    video = video_dedicace.creator_end_dedication_video
    dedicace = video_dedicace.dedicace.video
    return unless video.attached?

    # Paths to the uploaded files
    input_path = ActiveStorage::Blob.service.path_for(video.blob.key)
    theme_video_path = ActiveStorage::Blob.service.path_for(dedicace.blob.key)
    temp_output_path = "#{Rails.root.join("tmp/#{SecureRandom.uuid}.mp4")}"
    overlay_output_path = "#{Rails.root.join("tmp/#{SecureRandom.uuid}_overlay.mp4")}"
    transparent_video_path = "#{Rails.root.join("tmp/#{SecureRandom.uuid}_transparent.mp4")}"
    # output_video_path = "#{Rails.root}/tmp/#{SecureRandom.uuid}_processed_video.mp4"

    # Step 1: Reprocess video to MP4 with H.264 codec and AAC audio
    system(<<~CMD.squish)
      ffmpeg -y -i #{Shellwords.escape(input_path)} \
      -c:v libx264 -pix_fmt yuv420p -preset fast -crf 23 \
      -c:a aac -ar 44100 -r 30 \
      -movflags +faststart \
      #{Shellwords.escape(temp_output_path)}
    CMD

    p "+" * 100 + "python" + "+" * 100
    python_script = "#{Rails.root.join('lib/python/process_video.py')}"

    # Run Python script and capture output
    python_executable = ENV.fetch("PYTHON_EXECUTABLE", "python")
    stdout, stderr, status = Open3.capture3(
      python_executable,
      python_script,
      temp_output_path,
      transparent_video_path,
      theme_video_path
    )

    # Check if the Python script ran successfully
    raise "Python script failed: #{stderr}" unless status.success? && File.exist?(transparent_video_path)

    # Attach processed video
    video.blob.open do |file|
      File.open(transparent_video_path) do |processed_file|
        video.attach(io: processed_file, filename: "#{video.filename.base}.mp4", content_type: "video/mp4")
      end
    end
  ensure
    # Clean up temporary files
    [temp_output_path, overlay_output_path, transparent_video_path].each do |path|
      File.delete(path) if File.exist?(path)
    end
  end
end
