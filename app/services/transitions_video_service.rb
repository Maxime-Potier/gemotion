class TransitionsVideoService
  def initialize(temp_dir, command_runner: nil)
    @temp_dir = temp_dir
    @command_runner = command_runner || ->(command) { Kernel.system(command) }
  end

  def create_transition_wipelt_videos(videos, transition_types = [], transition_duration = Rails.application.config.transition_duration, custom_output_path = nil)
    # Map transition_type to FFmpeg xfade transition names
    transition_map = {
      "none" => "fade",
      "dissolve" => "fade",
      "flash" => "fadewhite",
      "directional" => "slideleft",
      "zoom" => "zoomin",
      "swap_instant" => "smoothleft",
      "radial" => "radial",
      "centered_drop" => "circlecrop",
      "cube" => "cube", # ffmpeg-concat
      "heart" => "heart" # ffmpeg-concat
    }

    # Return early if there are no videos or just one video
    return nil if videos.nil? || videos.empty?
    return videos.first if videos.length == 1

    # Paths
    output_video_path = custom_output_path || @temp_dir.join("final_video_with_transitions.mp4")

    # Normalize all videos
    normalized_videos = []
    videos.each_with_index do |video, index|
      normalized_path = @temp_dir.join("normalized_#{index}.mp4")
      normalize_video(video, normalized_path)
      normalized_videos << normalized_path
    end

    transition_outputs = []

    (0...normalized_videos.length - 1).each do |i|
      # Get the transition type for this pair or use default
      current_transition_type = transition_types[i] || "dissolve"
      ffmpeg_transition = transition_map[current_transition_type] || "fade"

      first_video = if transition_outputs.present?
                      Shellwords.escape(transition_outputs.last.to_s)
                    else
                      Shellwords.escape(normalized_videos[i].to_s)
                    end
      second_video = Shellwords.escape(normalized_videos[i + 1].to_s)

      # Get beginning video duration
      beginning_duration_cmd = "ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \"#{first_video}\""
      beginning_duration = `#{beginning_duration_cmd}`.strip.to_f

      # Adjust transition duration for this pair
      transition_duration_float = transition_duration.to_f
      actual_transition_duration = [transition_duration_float, beginning_duration - 0.1].max

      # Create transition between this pair of videos
      transition_output = @temp_dir.join("transition_#{i}_to_#{i + 1}.mp4")

      if (ffmpeg_transition == "cube" || ffmpeg_transition == "heart")
        ffmpeg_command = <<-CMD
          ffmpeg-concat -t #{ffmpeg_transition} -d #{transition_duration*1000} -o #{Shellwords.escape(transition_output.to_s)} #{first_video} #{second_video}
        CMD
      else
        ffmpeg_command = <<~CMD
          ffmpeg -i #{first_video} -i #{second_video} -filter_complex "
          [0:v]format=pix_fmts=yuv420p,scale=1920:1080[base];
          [1:v]format=pix_fmts=yuv420p,scale=1920:1080[next];
          [base][next]xfade=transition=#{ffmpeg_transition}:duration=#{transition_duration_float}:offset=#{[beginning_duration - transition_duration_float, 0].max}[out]" \
          -map "[out]" -map 0:a -c:v libx264 -c:a aac -crf 23 -preset veryfast #{Shellwords.escape(transition_output.to_s)}
        CMD
      end

      puts "Creating transition #{i + 1} of #{normalized_videos.length - 1}"
      run_command(ffmpeg_command)

      if File.exist?(transition_output) && File.size(transition_output) > 0
        transition_outputs << transition_output
      else
        puts "Warning: Failed to create transition #{i} to #{i + 1}"
      end
    end

    # If we couldn't create any transitions, return nil
    return nil if transition_outputs.empty?

    # Create a file list for concatenation
    # concat_list = @temp_dir.join("transitions_concat_list.txt")
    # File.open(concat_list, "w") do |file|
    # transition_outputs.each do |path|
    # file.puts("file '#{path}'")
    # end
    # end

    # Concatenate all transition segments into the final output
    # concat_command = <<~CMD
    #  ffmpeg -y -f concat -safe 0 -i #{Shellwords.escape(concat_list.to_s)} \
    #    -c copy #{Shellwords.escape(output_video_path.to_s)}
    # CMD

    copy_command = <<~CMD
      cp #{Shellwords.escape(transition_outputs.last.to_s)} #{Shellwords.escape(output_video_path.to_s)}
    CMD

    # puts "Concatenating all transitions"
    puts "Copy last transition as video output"
    # system(concat_command)
    run_command(copy_command)

    # Clean up intermediate files
    [*normalized_videos, *transition_outputs].each { |file| File.delete(file) if File.exist?(file) }

    # Return the final output path if it exists
    File.exist?(output_video_path) ? output_video_path : nil
  end

  def normalize_video(input_path, output_path)
    # Normalize video to a consistent resolution and frame rate
    ffmpeg_command = <<~CMD
      ffmpeg -i #{Shellwords.escape(input_path.to_s)} \
        -vf "scale=1920:1080,fps=30" \
        -c:v libx264 -crf 23 -preset veryfast \
        -c:a aac -b:a 128k \
        #{Shellwords.escape(output_path.to_s)}
    CMD

    raise "Failed to normalize video: #{input_path}" unless run_command(ffmpeg_command)
  end

  private

  def run_command(command)
    @command_runner.call(command)
  end
end
