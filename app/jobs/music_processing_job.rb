require "open3"

class MusicProcessingJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: false

  def perform(chapter_class_name, chapter_id)
    chapter_class = chapter_class_name.constantize
    chapter = chapter_class.find(chapter_id)

    unless chapter.custom_music.attached?
      Rails.logger.error "Custom music is not attached for #{chapter_class_name} ID #{chapter_id}"
      return
    end

    sanitized_class_name = chapter_class_name.underscore
    waveform_json_path = Rails.root.join("tmp", "waveform_#{sanitized_class_name}_#{chapter_id}.json")

    chapter.custom_music.blob.open do |music_file|
      _stdout, stderr, status = Open3.capture3(
        "audiowaveform", "-i", music_file.path, "-o", waveform_json_path.to_s,
        "--pixels-per-second", "50", "--bits", "8"
      )

      if status.success?
        waveform_data = File.read(waveform_json_path)
        chapter.update!(waveform: JSON.parse(waveform_data))
      else
        Rails.logger.error "Failed to generate waveform for #{chapter_class_name} ID #{chapter_id}: #{stderr}"
      end
    end
  rescue Errno::ENOENT => e
    Rails.logger.error "Unable to generate waveform for #{chapter_class_name} ID #{chapter_id}: #{e.message}"
  ensure
    File.delete(waveform_json_path) if waveform_json_path && File.exist?(waveform_json_path)
  end
end
