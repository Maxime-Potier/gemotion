class CombineVideoDedicaceJob < ApplicationJob

  queue_as :default

  sidekiq_options retry: true

  def perform(video_id)
    video = Video.find(video_id)
    video_dedicace = video.video_dedicace

    return false if video_dedicace.nil?

    ready_slots = video_dedicace.video_dedicace_slots.order(:slot).select do |slot|
      slot.status == "done" && slot.video.attached?
    end
    return false if ready_slots.empty?

    # Create temporary directory for processing
    timestamp = Time.now.to_i
    temp_dir = Rails.root.join("tmp", "video_combine_#{timestamp}")
    FileUtils.mkdir_p(temp_dir)
    output_path = temp_dir.join("final_output.mp4")

    begin
      # Download background image
      bg_path = Rails.root.join("app/assets/images/dedicace-carpool-background.jpg")

      # Prepare paths for temporary files
      input_videos = []
      filter_complex = []
      last_output = "0:v" # Start with background

      # Download and prepare each video
      ready_slots.each_with_index do |video_dedicace_slot, index|
        # Download video to temp directory
        video_path = temp_dir.join("input_#{index}.mp4")
        File.open(video_path, "wb") do |file|
          file.write(video_dedicace_slot.video.download)
        end
        input_videos << "-i #{video_path}"

        # Calculate position based on slot number
        case video_dedicace_slot.slot
        when 1 # Left passenger position
          x = "W/4-w/2" # 1/4 of the width from left, centered
          y = "H*0.75-h" # Lower part of frame
          scale = "iw*0.3" # Scale to 30% of original size
        when 2 # Center/back passenger position
          x = "W/2-w/2"         # Center horizontally
          y = "H*0.4-h"         # Higher up in the frame
          scale = "iw*0.25"     # Slightly smaller for depth perspective
        when 3 # Right passenger position
          x = "3*W/4-w/2" # 3/4 of the width from left, centered
          y = "H*0.75-h" # Lower part of frame
          scale = "iw*0.3" # Scale to 30% of original size
        end

        # Process video: scale and remove green background
        filter_complex << "[#{index + 1}:v]scale=#{scale}:-1,chromakey=0x00FF00:0.15:0.2[v#{index}]"

        # Overlay on previous result with proper centering
        filter_complex << "[#{last_output}][v#{index}]overlay=#{x}:#{y}:format=auto[v#{index}out]"

        # Update last output for next iteration
        last_output = "v#{index}out"
      end

      # Build ffmpeg command
      filter_str = filter_complex.join(";")

      Rails.logger.info("Starting video combination with filter: #{filter_str}")

      # Construct final command
      cmd = [
        "ffmpeg",
        "-loop 1", # Loop the background image
        "-t 30", # Limit duration to 5 seconds
        "-i #{bg_path}",           # Background image
        input_videos.join(" "),    # Input videos
        "-filter_complex",
        "\"#{filter_str}\"",       # Filter complex
        "-map \"[#{last_output}]\"", # Map the last output
        "-c:v libx264", # Video codec
        "-c:a aac",               # Audio codec
        "-ar 44100",              # Audio sample rate
        "-r 30",                  # Frame rate
        "-preset ultrafast", # Encoding preset
        "-t 30", # Ensure output is limited to 5 seconds
        "-pix_fmt yuv420p",       # Pixel format
        "-y",                     # Overwrite output file if exists
        output_path.to_s
      ].join(" ")

      Rails.logger.info("Executing ffmpeg command: #{cmd}")

      # Execute ffmpeg command
      unless system(cmd)
        Rails.logger.error("FFmpeg command failed")
        raise "Failed to execute ffmpeg command"
      end

      # Attach the combined video to the original video record
      raise "Failed to generate combined video" unless File.exist?(output_path)

      video_dedicace.creator_end_dedication_video.attach(
        io: File.open(output_path),
        filename: "final_dedicace_video_#{timestamp}.mp4",
        content_type: "video/mp4"
      )
      Rails.logger.info("Successfully attached final video to record")
      true
    rescue StandardError => e
      Rails.logger.error("Error in video combination: #{e.message}")
      false
    ensure
      # Clean up temporary files
      FileUtils.rm_rf(temp_dir)
    end
  end
end
