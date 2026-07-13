require "open3"
require "shellwords"
class RemoveBackgroundJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: false, log_level: :warn

  def perform(video_dedicace_slot_id, input_path, slot_number)
    video_dedicace_slot = VideoDedicaceSlot.find(video_dedicace_slot_id)

    logger.info("Processing video #{video_dedicace_slot.video_dedicace.id} with slot number #{slot_number}")

    video_dedicace_slot.status = "processing"
    video_dedicace_slot.save!
    logger.info("Video status set to processing")
    # Create temporary paths
    timestamp = Time.now.to_i
    converted_path = Rails.root.join("tmp", "converted_video_#{video_dedicace_slot_id}_#{slot_number}_#{timestamp}.mp4")
    output_path = Rails.root.join("tmp", "processed_video_#{video_dedicace_slot_id}_#{slot_number}_#{timestamp}.mp4")

    logger.info("Input path: #{input_path}")
    logger.info("Converted path: #{converted_path}")
    p("Output path: #{output_path}")

    # First convert WebM to MP4 with optimized settings
    p("Converting WebM to MP4")
    convert_result = system("ffmpeg -i #{Shellwords.escape(input_path)} " \
                          "-c:v libx264 " \
                          "-preset veryfast " \
                          "-crf 23 " \
                          "-tune zerolatency " \
                          "-movflags +faststart " \
                          "-c:a aac " \
                          "-ac 2 " \
                          "-b:a 128k " \
                          "-y " \
                          "#{Shellwords.escape(converted_path)}")

    unless convert_result
      video_dedicace_slot.status = "error"
      video_dedicace_slot.save
      logger.error("Failed to convert WebM to MP4")
      return {
        success: false,
        errors: ["Failed to convert video format"]
      }
    end

    unless File.exist?(converted_path)
      video_dedicace_slot.status = "error"
      video_dedicace_slot.save!
      logger.error("Converted video file not created")
      return {
        success: false,
        errors: ["Converted video file not created"]
      }
    end

    # Call Python script with the correct Python environment
    python_script = Rails.root.join("lib/scripts/remove_background.py")

    # Use the system Python or the virtual environment Python
    python_path = [
      ENV["PYTHON_BIN"],
      "/venv/bin/python",
      Rails.root.join("venv/bin/python").to_s,
      "python3"
    ].compact.find { |path| path == "python3" || File.executable?(path) }

    # Execute the Python script and capture output
    logger.info("Executing Python script")
    result = system("#{python_path} #{python_script} #{Shellwords.escape(converted_path)} #{Shellwords.escape(output_path)}")

    logger.info("Result: #{result}")

    unless result
      video_dedicace_slot.status = "error"
      video_dedicace_slot.save
     logger.error("Failed to process video with Python script")
      return {
        success: false,
        errors: ["Failed to process video"]
      }
    end

    unless File.exist?(output_path)
      logger.error("Output video file not created")
      return {
        success: false,
        errors: ["Output video file not created"]
      }
    end

    begin
      # Attach processed video to video_dedicace
      video_dedicace_slot.video.attach(
        io: File.open(output_path),
        filename: "processed_video_#{slot_number}_#{timestamp}.mp4",
        content_type: "video/mp4"
      )

      # Generate preview from first frame and remove green background
      preview_path = Rails.root.join("tmp", "preview_#{video_dedicace_slot_id}_#{slot_number}_#{timestamp}.png")
      preview_result = system("ffmpeg -i #{output_path} -vframes 1 -vf \"chromakey=0x00FF00:0.1:0.2\" -f image2 -update 1 #{preview_path}")

      unless preview_result
        logger.error("Failed to generate preview")
        return {
          success: false,
          errors: ["Failed to generate preview"]
        }
      end

      logger.info("Preview generated successfully")

      if File.exist?(preview_path)
        video_dedicace_slot.preview.attach(
          io: File.open(preview_path),
          filename: "preview_#{slot_number}_#{timestamp}.png",
          content_type: "image/png"
        )
      end

      logger.info("Preview attached successfully")
      logger.info("Preview path: #{preview_path}")
      video_dedicace_slot.status = "done"
      video_dedicace_slot.save

      logger.info("Video processing completed successfully")
      {
        success: true
      }
    rescue StandardError => e
      logger.error("Error in video processing: #{e.message}")
      {
        success: false,
        errors: ["Error processing video: #{e.message}"]
      }
    ensure
      # Clean up temporary files
      File.delete(input_path) if File.exist?(input_path)
      File.delete(converted_path) if File.exist?(converted_path)
      File.delete(output_path) if File.exist?(output_path)
      File.delete(preview_path) if File.exist?(preview_path)
    end
  end
end
