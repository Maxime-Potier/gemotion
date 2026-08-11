require "zip"
require "open3"
require "shellwords"

class ContentDedicaceService
  LANDSCAPE_IMAGE_FILTER = "scale=1280:720:force_original_aspect_ratio=decrease," \
                           "pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1".freeze
  STILL_IMAGE_LOOP_OPTION = "-stream_loop -1".freeze
  MP4_FASTSTART_OPTION = "-movflags +faststart".freeze

  def initialize(video)
    @video = video

    @temp_dir = Rails.root.join("tmp", SecureRandom.hex)
    FileUtils.mkdir_p(@temp_dir)

    @archive_path = @temp_dir.join("video_mlt.zip")
    Zip::File.open(@archive_path, Zip::File::CREATE) {}

    @ts_videos = []

    @collaborations = @video.collaborations.where.not(invited_user: nil)

    @previews_length = ""

    @video_length = ""

    @imgs_to_video_duration_in_seconds = "3"

    @previews_duration = ""

    @introduction_duration = ""

    @mlt_content = <<-MLT
    <mlt LC_NUMERIC="C" version="7.28.0" title="Shotcut version 24.10.29" producer="main_bin">
      <profile description="HD 1080p 30fps" id="HD 1080p 30fps" width="1920" height="1080" frame_rate="30" />
    MLT
  end

  def call
    persist_progress(1)
    preview_assets = fetch_preview_assets
    chapter_assets = fetch_chapter_assets

    @invited_users = @collaborations.includes(:invited_user).map(&:invited_user)
    collaborators_chapters_assets = fetch_collaborator_chapter_assets(@invited_users)

    united_chapter_assets = chapter_assets + collaborators_chapters_assets

    if chapter_assets.empty? || preview_assets.empty?
      return { error: "Aucune vidéo, photo ou aperçu de chapitre disponible." }
    end

    previews_duration_calc(preview_assets.count) if @video.by_chapters?

    # Process the introduction defining  @introduction_mp4_path and @introduction_duration
    prepare_progress_stage(2, 8, 1)
    process_introduction

    # Process the Previews with texts and transitions
    prepare_progress_stage(8, 35, (preview_assets.count * 3) + 2)
    process_previews(preview_assets)

    # Process the chapters
    prepare_progress_stage(35, 75, chapter_ffmpeg_command_count(united_chapter_assets))
    process_chapters(united_chapter_assets)

    if @video.video_type == "colab" && @video.dedicace.present?
      approved_collaborations = @collaborations.count do |collaboration|
        collaboration.collaborator_dedicace.present? && collaboration.collaborator_dedicace.approved_by_creator
      end
      prepare_progress_stage(75, 80, 1 + approved_collaborations)
      dedicace_video
      @collaborations.each do |collaboration|
        collaborator_dedicace_video(collaboration)
      end
    end

    prepare_progress_stage(80, 94, final_ffmpeg_command_count)
    final_video_path = concatenate_final_video

    return { error: "La concaténation des vidéos finales a échoué." } unless File.exist?(final_video_path)

    set_final_video_length(final_video_path)

    finalize_mlt
    final_cut_pro_archive_path = build_final_cut_pro_archive(final_video_path)

    prepare_progress_stage(94, 99, 1)
    attach_final_video(final_video_path, final_cut_pro_archive_path)
  rescue StandardError => e
    # Log the error or take other actions if necessary
    Rails.logger.error("Error in call method: #{e.message}")
    { error: e.message }
  ensure
    # Always clean up the temp directory
    # FileUtils.rm_rf(@temp_dir)
  end

  private

  def previews_duration_calc(preview_count)
    total_seconds = preview_count * 3
    @previews_duration = Time.at(total_seconds).utc.strftime("%H:%M:%S.%3N")
  end

  def fetch_preview_assets
    ordered_filenames = @video.previews_order
    if ordered_filenames.nil?
      @video.video_previews.includes(:preview).sort_by(&:order)
    else
      @video.video_previews.includes(:preview).sort_by do |video_preview|
        ordered_filenames.index(video_preview.preview.image.blob.filename.to_s) || Float::INFINITY
      end
    end
  end

  def fetch_chapter_assets
    @video.video_chapters.includes(:chapter_type).sort_by(&:order).map do |vc|
      {
        videos: vc.ordered_videos,
        photos: vc.ordered_photos,
        music: if vc.custom_music.attached?
                 vc.custom_music
               else
                 (vc.video_music.nil? ? nil : vc.video_music.music)
               end,
        chapter_type_image: vc.chapter_type.image,
        text: vc.text,
        text_family: vc.text_family,
        text_style: vc.text_style,
        text_size: vc.text_size,
        slide_color: vc.slide_color
      }
    end
  end

  def fetch_collaborator_chapter_assets(collaborators)
    collaborators.flat_map do |collaborator|
      collaborator.collaborator_chapters.approved.includes(:chapter_type).order(:order).map do |vc|
        {
          videos: vc.ordered_videos,
          photos: vc.ordered_photos,
          music: vc.collaborator_music&.music,
          chapter_type_image: vc.chapter_type&.image,
          text: vc.text,
          text_family: vc.text_family,
          text_style: vc.text_style,
          text_size: vc.text_size,
          slide_color: vc.slide_color
        }
      end
    end
  end

  def process_introduction
    # The introoduction file is now added in process_previews method with the transitions
    introduction_input_path = Rails.root.join("app/assets/videos/previews/#{@video.introduction_video}.mp4")
    introduction_output_path = @temp_dir.join("introduction.ts")
    p "+" * 100 + "introduction" + "+" * 100
    system("ffmpeg -y -i \"#{introduction_input_path}\" -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 -r 30 -f mpegts \"#{introduction_output_path}\"")
    p "-" * 100 + "introduction" + "-" * 100

    unless File.exist?(introduction_output_path) && File.size(introduction_output_path) > 0
      raise "Error: Failed to create introduction file"
    end

    @introduction_mp4_path = introduction_output_path
    output = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{@introduction_mp4_path.to_s.shellescape}`

    raise "Error: Could not retrieve introduction video duration." if output.strip.empty?

    @introduction_duration = Time.at(output.strip.to_f).utc.strftime("%H:%M:%S.%3N")
  end

  def process_previews(preview_assets)
    # First, process each preview image individually
    mp4_preview_files = []
    preview_transitions = []

    preview_assets.each_with_index do |preview, index|
      preview_path = ActiveStorage::Blob.service.send(:path_for, preview.preview.image.key)
      output_path = @temp_dir.join("preview_#{index}.ts")
      mp4_output_path = @temp_dir.join("preview_#{index}.mp4")

      # Check if this preview has text overlay settings
      preview_text = preview.preview.text
      text_position = preview.preview.text_position
      start_time = preview.preview.start_time
      duration = preview.preview.duration || @imgs_to_video_duration_in_seconds.to_f
      font_type = preview.preview.font_type
      font_style = preview.preview.font_style
      font_size = preview.preview.font_size
      animation = preview.preview.animation
      text_color = preview.preview.text_color
      transition_type = preview.preview.transition_type || "dissolve"

      # Print debug information about the preview settings
      puts "Preview #{index}: Text='#{preview_text}', Animation='#{animation}', Transition='#{transition_type}'"

      # Store the transition type for each preview
      preview_transitions << transition_type

      p "+" * 100 + "process_preview" + "+" * 100

      # Use default values if not provided
      duration ||= @imgs_to_video_duration_in_seconds.to_f
      start_time ||= 0

      # Build the ffmpeg filter command based on text overlay properties
      if preview_text.present?
        fontfile = Rails.root.join("app/assets/images/fonts/#{font_type || 'Arial'}-#{font_style}.ttf").to_s
        font_size ||= 80
        text_color ||= "white"

        # Determine text position
        text_position ||= "middle" # Default to middle
        position_params = case text_position
                          when "top"
                            "x=(w-text_w)/2:y=h/10"
                          when "bottom"
                            "x=(w-text_w)/2:y=h-h/10-text_h"
                          when "middle"
                            "x=(w-text_w)/2:y=(h-text_h)/2"
                          when "top-left"
                            "x=w/10:y=h/10"
                          when "top-right"
                            "x=w-w/10-text_w:y=h/10"
                          when "bottom-left"
                            "x=w/10:y=h-h/10-text_h"
                          when "bottom-right"
                            "x=w-w/10-text_w:y=h-h/10-text_h"
                          else
                            "x=(w-text_w)/2:y=(h-text_h)/2"
                          end

        # Add animation if specified
        animation_params = case animation
                           when "fade-in"
                             ":alpha='if(lt(t,#{start_time}),0,if(lt(t,#{start_time + 0.5}),(t-#{start_time})/0.5,1))'"
                           when "slide-in"
                             ":x='if(lt(t,#{start_time}),-text_w,if(lt(t,#{start_time + 0.5}),((t-#{start_time})/0.5)*(w-text_w)/2+(-text_w),#{position_params.split(':')[0].sub(
                               'x=', ''
                             )}))'"
                           when "zoom-in"
                             ":fontsize='if(lt(t,#{start_time}),0,if(lt(t,#{start_time + 0.5}),(t-#{start_time})/0.5*#{font_size},#{font_size}))'"
                           when "typewriter"
                             # Typewriter effect is complex in ffmpeg; we'll do a simple version
                             # We need to escape single quotes and create a proper sequence for the typewriter effect
                             typewriter_text = preview_text.chars.each_with_index.map do |c, i|
                               preview_text[0..i].gsub("'", "\\\\'")
                             end.join('\\\\|')

                             ":text='#{typewriter_text}':enable='between(t,#{start_time},#{start_time + duration})'"
                           else
                             ":enable='between(t,#{start_time},#{start_time + duration})'"
                           end

        # Build the complete drawtext filter
        drawtext_filter = "drawtext=text='#{preview_text}':fontfile='#{fontfile}':" \
                         "fontcolor=#{text_color}:fontsize=#{font_size}:#{position_params}:" \
                         "box=1:boxcolor=black@0.0:boxborderw=5#{animation_params}"

        # Apply the filter to the image
        ffmpeg_command = "ffmpeg -y #{STILL_IMAGE_LOOP_OPTION} -i \"#{preview_path}\" " \
          "-f lavfi -i anullsrc=r=44100:cl=stereo " \
          "-c:v libx264 -c:a aac -t #{@imgs_to_video_duration_in_seconds} -r 30 -vf \"#{LANDSCAPE_IMAGE_FILTER},#{drawtext_filter}\" -pix_fmt yuvj420p " \
          "\"#{mp4_output_path}\""

        puts "Executing FFmpeg command for preview #{index} with animation '#{animation}':"
        puts ffmpeg_command

        # Execute the command
        system(ffmpeg_command)
      else
        # No text overlay, just use the standard processing
        system(
          "ffmpeg -y #{STILL_IMAGE_LOOP_OPTION} -i \"#{preview_path}\" " \
          "-f lavfi -i anullsrc=r=44100:cl=stereo " \
          "-c:v libx264 -c:a aac -t #{@imgs_to_video_duration_in_seconds} -r 30 -vf \"#{LANDSCAPE_IMAGE_FILTER}\" -pix_fmt yuvj420p " \
          "\"#{mp4_output_path}\""
        )
      end
      p "-" * 100 + "process_preview" + "-" * 100

      # Store mp4 path for transitions
      mp4_preview_files << mp4_output_path
    end

    # Initialize transition service
    transitions_service = TransitionsVideoService.new(@temp_dir, command_runner: method(:system))

    # Prepare all videos for transitions including introduction if available
    all_videos = []
    all_transitions = []

    # Add introduction video if it exists
    if @introduction_mp4_path && File.exist?(@introduction_mp4_path)
      all_videos << @introduction_mp4_path
      # Use first preview's transition type for the transition from intro
      all_transitions << (preview_assets.first&.preview&.transition_type || "dissolve")
    end

    # Add all preview videos
    all_videos.concat(mp4_preview_files)
    # Add all transitions except for the first one which we already included if we have introduction
    if @introduction_mp4_path && File.exist?(@introduction_mp4_path)
      all_transitions.concat(preview_transitions.drop(1)) if mp4_preview_files.size > 1
    else
      # If no introduction, we need all transitions
      all_transitions.concat(preview_transitions)
    end

    # Special case handling for no videos or single video
    return if all_videos.empty?

    # Process all videos with transitions at once
    all_transitions_output = @temp_dir.join("all_previews_with_transitions.mp4")

    begin
      # Single call to create all transitions
      transitions_service.create_transition_wipelt_videos(
        all_videos,
        all_transitions,
        Rails.application.config.transition_duration,
        all_transitions_output
      )

      if File.exist?(all_transitions_output) && File.size(all_transitions_output) > 0
        # Convert to TS format for the main processing pipeline
        transitioned_ts_output = @temp_dir.join("previews_with_transitions.ts")
        system("ffmpeg -y -i \"#{all_transitions_output}\" -c copy -f mpegts \"#{transitioned_ts_output}\"")

        # Add to our video list
        @ts_videos << transitioned_ts_output.to_s

        # Add to MLT
        add_to_mlt_video(transitioned_ts_output, "previews_with_transitions.ts", "previews_with_transitions")
        upload_to_archive("previews_with_transitions.ts", transitioned_ts_output)

        # Clean up
        File.delete(all_transitions_output) if File.exist?(all_transitions_output)
      else
        # If combined transitions failed, fall back to adding videos individually
        puts "Warning: Failed to create transitions, adding individual videos"

        # Add introduction directly if it exists
        if @introduction_mp4_path && File.exist?(@introduction_mp4_path)
          intro_ts = @temp_dir.join("introduction.ts")
          system("ffmpeg -y -i \"#{@introduction_mp4_path}\" -c copy -f mpegts \"#{intro_ts}\"")
          @ts_videos << intro_ts.to_s
        end

        # Add each preview individually
        mp4_preview_files.each_with_index do |file, index|
          output_path = @temp_dir.join("preview_#{index}.ts")
          system("ffmpeg -y -i \"#{file}\" -c copy -f mpegts \"#{output_path}\"")

          next unless File.exist?(output_path) && File.size(output_path) > 0

          @ts_videos << output_path.to_s
          add_to_mlt_img(output_path, "preview_#{index}.ts", "preview_#{index}", 3)
          upload_to_archive("preview_#{index}.ts", output_path)
        end
      end
    rescue StandardError => e
      puts "Error processing transitions: #{e.message}"

      # Fall back to adding videos individually
      # Add introduction directly if it exists
      if @introduction_mp4_path && File.exist?(@introduction_mp4_path)
        intro_ts = @temp_dir.join("introduction.ts")
        system("ffmpeg -y -i \"#{@introduction_mp4_path}\" -c copy -f mpegts \"#{intro_ts}\"")
        @ts_videos << intro_ts.to_s
      end

      # Add each preview individually
      mp4_preview_files.each_with_index do |file, index|
        output_path = @temp_dir.join("preview_#{index}.ts")
        system("ffmpeg -y -i \"#{file}\" -c copy -f mpegts \"#{output_path}\"")

        next unless File.exist?(output_path) && File.size(output_path) > 0

        @ts_videos << output_path.to_s
        add_to_mlt_img(output_path, "preview_#{index}.ts", "preview_#{index}", 3)
        upload_to_archive("preview_#{index}.ts", output_path)
      end
    end

    # Clean up the original preview files
    mp4_preview_files.each { |file| File.delete(file) if File.exist?(file) }
  end

  def process_chapters(chapter_assets)
    chapter_assets.each_with_index do |assets, chapter_index|
      chapter_music_path = fetch_chapter_music(assets)
      text_output_path = process_chapter_intro(assets, chapter_index)

      return if text_output_path.nil?

      process_videos(assets, chapter_index)
      process_photos(assets, chapter_index)

      concatenate_chapter_videos(chapter_index, assets, chapter_music_path)
    end
  end

  def fetch_chapter_music(assets)
    return unless @video.by_chapters?

    if assets[:music].is_a?(ActiveStorage::Attached::One)
      ActiveStorage::Blob.service.send(:path_for, assets[:music].key)
    elsif assets[:music] # For other types of music assets
      ActiveStorage::Blob.service.send(:path_for, assets[:music].music.key) if assets[:music]
    end
  end

  def process_chapter_intro(assets, chapter_index)
    if assets[:chapter_type_image]
      chapter_image_path = ActiveStorage::Blob.service.send(:path_for,
                                                            assets[:chapter_type_image].key)
    end
    chapter_text = assets[:text]
    chapter_text_family = assets[:text_family]
    chapter_text_style = assets[:text_style]
    chapter_text_size = assets[:text_size]
    return nil unless chapter_image_path && chapter_text.present?

    text_output_path = @temp_dir.join("chapter_intro_#{chapter_index}.ts")
    p "+" * 100 + "process_chapter_intro" + "+" * 100
    # system(
    #   "ffmpeg -y -loop 1 -i \"#{chapter_image_path}\" " \
    #   "-f lavfi -i anullsrc=r=44100:cl=stereo " \
    #   "-vf \"scale=1280:720, drawtext=text='#{chapter_text}':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2\" " \
    #   "-t #{@imgs_to_video_duration_in_seconds} -c:v libx264 -pix_fmt yuvj420p -c:a aac -r 30 -shortest \"#{text_output_path}\""
    # )
    fontfile = chapter_text_family
    fontfile = Rails.root.join("app/assets/images/fonts/#{chapter_text_family}-#{chapter_text_style}.ttf").to_s

    system(
      "ffmpeg -y #{STILL_IMAGE_LOOP_OPTION} -i \"#{chapter_image_path}\" " \
      "-f lavfi -i anullsrc=r=44100:cl=stereo " \
      "-vf \"#{LANDSCAPE_IMAGE_FILTER},drawtext=text='#{chapter_text}':fontfile='#{fontfile}':" \
      "fontcolor=white:fontsize=#{chapter_text_size}:x=(w-text_w)/2:y=(h-text_h)/2:" \
      "box=1:boxcolor=black@0.5:boxborderw=10\" " \
      "-t #{@imgs_to_video_duration_in_seconds} -c:v libx264 -pix_fmt yuvj420p -c:a aac -r 30 -shortest \"#{text_output_path}\""
    )

    p "-" * 100 + "process_chapter_intro" + "-" * 100
    @ts_videos << text_output_path.to_s
    add_to_mlt_img(text_output_path, "chapter_intro_#{chapter_index}.ts", "chapter_intro_#{chapter_index}", 3)
    upload_to_archive("chapter_intro_#{chapter_index}.ts", text_output_path)

    text_output_path
  end

  def process_videos(assets, chapter_index)
    assets[:videos].each_with_index do |video, video_index|
      input_path = ActiveStorage::Blob.service.send(:path_for, video.key)
      output_path = @temp_dir.join("video_#{chapter_index}_#{video_index}.ts")
      p "+" * 100 + "process_video" + "+" * 100
      system("ffmpeg -y -i \"#{input_path}\" -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 -r 30 \"#{output_path}\"")
      p "-" * 100 + "process_video" + "-" * 100
      @ts_videos << output_path.to_s
      add_to_mlt_video(output_path, "video_#{chapter_index}_#{video_index}.ts", "video_#{chapter_index}_#{video_index}")
      upload_to_archive("video_#{chapter_index}_#{video_index}.ts", output_path)
    end
  end

  def process_photos(assets, chapter_index)
    assets[:photos].each_with_index do |photo, photo_index|
      input_path = ActiveStorage::Blob.service.send(:path_for, photo.key)
      output_path = @temp_dir.join("photo_#{chapter_index}_#{photo_index}.ts")
      p "+" * 100 + "process_photo" + "+" * 100
      processed = system(
        "ffmpeg -y #{STILL_IMAGE_LOOP_OPTION} -i \"#{input_path}\" -f lavfi -i anullsrc=r=44100:cl=stereo " \
        "-c:v libx264 -t #{@imgs_to_video_duration_in_seconds} -vf \"#{LANDSCAPE_IMAGE_FILTER}\" " \
        "-map 0:v -map 1:a -c:a aac -pix_fmt yuvj420p -r 30 \"#{output_path}\""
      )
      p "-" * 100 + "process_photo" + "-" * 100
      unless processed && File.exist?(output_path) && File.size(output_path).positive?
        raise "Failed to process photo #{photo.filename}"
      end

      @ts_videos << output_path.to_s
      add_to_mlt_img(output_path, "photo_#{chapter_index}_#{photo_index}.ts", "photo_#{chapter_index}_#{photo_index}",
                     3)
      upload_to_archive("photo_#{chapter_index}_#{photo_index}.ts", output_path)
    end
  end

  def concatenate_chapter_videos(chapter_index, assets, chapter_music_path)
    chapter_ts_files = @ts_videos.last((assets[:videos].count + assets[:photos].count + 1)) # +1 for the intro
    chapter_ts_file_list = chapter_ts_files.join("|")
    concatenated_ts_path = @temp_dir.join("chapter_#{chapter_index}_concatenated.ts")
    p "+" * 100 + "concatenate_chapter_video" + "+" * 100
    system("ffmpeg -y -fflags +discardcorrupt -i \"concat:#{chapter_ts_file_list}\" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 44100 -f mpegts -fflags +genpts \"#{concatenated_ts_path}\"")
    p "-" * 100 + "concatenate_chapter_video" + "-" * 100

    # Convert the chapter TS to MP4
    chapter_concatenated_video_path = @temp_dir.join("chapter_#{chapter_index}_concatenated_video.mp4")
    p "+" * 100 + "concatenate_chapter_video_to_mp4" + "+" * 100
    system("ffmpeg -y -fflags +discardcorrupt -i \"#{concatenated_ts_path}\" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 44100 \"#{chapter_concatenated_video_path}\"")
    p "-" * 100 + "concatenate_chapter_video_to_mp4" + "-" * 100

    if @video.by_chapters? && chapter_music_path
      add_music_to_chapter(chapter_concatenated_video_path, chapter_music_path, chapter_index)
      add_to_mlt_music(chapter_music_path, "music_#{chapter_index}.mp3", "music_#{chapter_index}")
      upload_to_archive("music_#{chapter_index}.mp3", chapter_music_path)
    else
      @ts_videos << chapter_concatenated_video_path.to_s
    end
  end

  def add_music_to_chapter(chapter_concatenated_video_path, chapter_music_path, chapter_index)
    final_chapter_video_path = @temp_dir.join("final_chapter_#{chapter_index}_video_with_music.mp4")
    p "+" * 100 + "add_music_to_chapter" + "+" * 100
    system(
      "ffmpeg -y -i \"#{chapter_concatenated_video_path}\" -i \"#{chapter_music_path}\" " \
      "-filter_complex \"anullsrc=channel_layout=stereo:sample_rate=44100[a0];[1:a:0]volume=0.5[a1];[a0][a1]amix=inputs=2:duration=shortest[aout]\" " \
      "-map 0:v:0 -map \"[aout]\" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 44100 #{MP4_FASTSTART_OPTION} -shortest \"#{final_chapter_video_path}\""
    )
    p "-" * 100 + "add_music_to_chapter" + "-" * 100
    unless File.exist?(final_chapter_video_path)
      raise "L'ajout de la musique de chapitre a échoué pour le chapitre #{chapter_index + 1}."
    end

    @ts_videos << final_chapter_video_path.to_s
  end

  def dedicace_video
    dedicace_input_path = ActiveStorage::Blob.service.send(:path_for,
                                                           @video.video_dedicace.creator_end_dedication_video.key)
    dedicace_output_path = @temp_dir.join("dedicace.ts")
    p "+" * 100 + "dedicace_video" + "+" * 100
    system("ffmpeg -y -i \"#{dedicace_input_path}\" -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 -r 30 -f mpegts \"#{dedicace_output_path}\"")
    p "-" * 100 + "dedicace_video" + "-" * 100
    @ts_videos << dedicace_output_path.to_s
    add_to_mlt_video(dedicace_output_path, "dedicace.ts", "dedicace")
    upload_to_archive("dedicace.ts", dedicace_output_path)
  end

  def collaborator_dedicace_video(collaboration)
    p "*" * 100
    p "+" * 100 + "collaborator_dedicace_video counter" + "+" * 100
    p "*" * 100
    unless collaboration.collaborator_dedicace.present? && collaboration.collaborator_dedicace.approved_by_creator
      return
    end

    dedicace_input_path = ActiveStorage::Blob.service.send(:path_for,
                                                           collaboration.collaborator_dedicace.creator_end_dedication_video.key)
    dedicace_output_path = @temp_dir.join("collaboration_#{collaboration.id}_dedicace.ts")
    p "+" * 100 + "dedicace_video" + "+" * 100
    system("ffmpeg -y -i \"#{dedicace_input_path}\" -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 -r 30 -f mpegts \"#{dedicace_output_path}\"")
    p "-" * 100 + "dedicace_video" + "-" * 100
    @ts_videos << dedicace_output_path.to_s
    add_to_mlt_video(dedicace_output_path, "collaboration_#{collaboration.id}_dedicace.ts",
                     "collaboration_#{collaboration.id}_dedicace")
    upload_to_archive("collaboration_#{collaboration.id}_dedicace.ts", dedicace_output_path)
  end

  def concatenate_final_video
    final_music_path = ActiveStorage::Blob.service.send(:path_for, @video.music.music.key) if @video.whole_video?

    final_video_ts_file_list = @ts_videos.join("|")
    final_concatenated_ts_path = @temp_dir.join("final_concatenated.ts")
    p "+" * 100 + "concatenate_final_video_ts" + "+" * 100
    system("ffmpeg -y -fflags +discardcorrupt -i \"concat:#{final_video_ts_file_list}\" -c copy -f mpegts \"#{final_concatenated_ts_path}\"")
    p "-" * 100 + "concatenate_final_video_ts" + "-" * 100

    # Convert the final TS to MP4
    final_video_path = @temp_dir.join("final_video.mp4")
    if @video.whole_video? && final_music_path

      @final_timeline_paths = @ts_videos.dup

      add_to_mlt_music(final_music_path, "music_whole_video.mp3", "music_whole_video")
      upload_to_archive("music_whole_video.mp3", final_music_path)

      p "+" * 100 + "concatenate_final_video_with_music_on_whole_video" + "+" * 100
      system(
        "ffmpeg -y -i \"#{final_concatenated_ts_path}\" -i \"#{final_music_path}\" " \
        "-filter_complex \"anullsrc=channel_layout=stereo:sample_rate=44100[a0];[1:a:0]volume=0.5[a1];[a0][a1]amix=inputs=2:duration=shortest[aout]\" " \
        "-map 0:v:0 -map \"[aout]\" -c:v libx264 -pix_fmt yuv420p -r 30 -c:a aac -ar 44100 #{MP4_FASTSTART_OPTION} -shortest \"#{final_video_path}\""
      )
      p "-" * 100 + "concatenate_final_video_with_music_on_whole_video" + "-" * 100
    else
      @final_timeline_paths = rebuild_final_video_with_music_by_chapters(final_video_path)
    end
    final_video_path
  end

  def rebuild_final_video_with_music_by_chapters(final_video_path)
    final_chapter_videos_with_music = @ts_videos.grep(/final_chapter_\d+_video_with_music\.mp4/)

    # Convert .mp4 videos to .ts format if needed
    final_chapter_videos_with_music.each do |video|
      mp4_path = video
      ts_path = mp4_path.sub(/\.mp4$/, ".ts")

      next if File.exist?(ts_path)

      p "+" * 100 + "Convert final_chapters_videos_with_music to .ts format if needed" + "+" * 100
      system("ffmpeg -y -i \"#{mp4_path}\" -c:v libx264 -pix_fmt yuv420p -c:a aac -ar 44100 -r 30 -bsf:v h264_mp4toannexb -f mpegts \"#{ts_path}\"")
      p "-" * 100 + "Convert final_chapters_videos_with_music to .ts format if needed" + "-" * 100
    end

    transitioned_previews = @ts_videos.grep(/previews_with_transitions\.ts$/)
    final_chapter_videos_introduction = transitioned_previews.empty? ? @ts_videos.grep(/introduction\.ts$/) : []
    final_chapter_videos_previews = transitioned_previews.presence || @ts_videos.grep(/preview_\d+\.ts/)
    final_chapter_videos_with_music_ts = final_chapter_videos_with_music.map { |video| video.sub(/\.mp4$/, ".ts") }

    if @video.video_type == "colab" && @video.dedicace.present?
      final_chapter_videos_dedicace = @ts_videos.grep(/dedicace\.ts/)

      collaborator_dedicace_videos = @collaborations.flat_map do |collaboration|
        @ts_videos.grep(/collaboration_#{collaboration.id}_dedicace\.ts/)
      end.uniq

      all_dedicaces = final_chapter_videos_dedicace + collaborator_dedicace_videos

      all_videos_to_concat = final_chapter_videos_introduction +
                             final_chapter_videos_previews +
                             final_chapter_videos_with_music_ts +
                             all_dedicaces.uniq
    else
      all_videos_to_concat = final_chapter_videos_introduction + final_chapter_videos_previews + final_chapter_videos_with_music_ts
    end

    # Create a text file with the paths of the videos to concatenate
    concat_file_path = File.join(@temp_dir, "concat_list.txt")
    File.open(concat_file_path, "w") do |f|
      all_videos_to_concat.each do |video|
        f.puts("file '#{video}'")
      end
    end

    p "+" * 100 + "concatenate_final_video_with_music_by_chapter_video" + "+" * 100
    system(
      "ffmpeg -y -f concat -safe 0 -i \"#{concat_file_path}\" -c:v libx264 -pix_fmt yuv420p " \
      "-r 30 -c:a aac -ar 44100 #{MP4_FASTSTART_OPTION} \"#{final_video_path}\""
    )
    p "-" * 100 + "concatenate_final_video_with_music_by_chapter_video" + "-" * 100

    all_videos_to_concat
  end

  def build_final_cut_pro_archive(final_video_path)
    timeline_paths = Array(@final_timeline_paths).select { |path| File.exist?(path) && File.size(path).positive? }
    timeline_paths = [final_video_path] if timeline_paths.empty?

    FinalCutProExportService.new(
      video: @video,
      media_paths: timeline_paths,
      output_dir: @temp_dir
    ).call
  rescue StandardError => e
    Rails.logger.error("Unable to build Final Cut Pro export: #{e.message}")
    nil
  end

  def attach_final_video(final_video_path, final_cut_pro_archive_path = nil)
    @video.final_video.attach(io: File.open(final_video_path), filename: "final_video.mp4")

    watermarked_video_path = generate_watermarked_video(final_video_path)
    if File.exist?(watermarked_video_path)
      @video.final_video_with_watermark.attach(io: File.open(watermarked_video_path),
                                               filename: "final_video_with_watermark.mp4")
      File.delete(watermarked_video_path) # Clean up the temporary file
    end

    if File.exist?(@archive_path)
      @video.final_video_xml.attach(io: File.open(@archive_path), filename: "video_mlt.zip")
    end

    return unless final_cut_pro_archive_path && File.exist?(final_cut_pro_archive_path)

    @video.final_cut_pro_archive.attach(
      io: File.open(final_cut_pro_archive_path),
      filename: "final_cut_pro_#{@video.id}.zip",
      content_type: "application/zip"
    )
  end

  def generate_watermarked_video(video_path)
    watermark_image_path = Rails.root.join("app/assets/images/bigger-watermark.png")
    watermarked_video_path = @temp_dir.join("watermarked_#{@video.id}.mp4")
    # watermarked_video_path = Rails.root.join("tmp", "watermarked_#{@video.id}.mp4")

    ffmpeg_command = <<~CMD
      ffmpeg -i "#{video_path}" -i "#{watermark_image_path}" -i "#{watermark_image_path}" -filter_complex "
        [0:v][1:v]overlay=10:10[video1];
        [video1][2:v]overlay=W-w-10:H-h-10" -c:a copy #{MP4_FASTSTART_OPTION} "#{watermarked_video_path}"
    CMD

    system(ffmpeg_command)
    watermarked_video_path
  end

  def chapter_ffmpeg_command_count(chapter_assets)
    chapter_assets.sum do |assets|
      music_command = @video.by_chapters? && assets[:music].present? ? 1 : 0
      3 + assets[:videos].count + assets[:photos].count + music_command
    end
  end

  def final_ffmpeg_command_count
    return 2 if @video.whole_video?

    chapter_conversions = @ts_videos.count { |path| path.match?(/final_chapter_\d+_video_with_music\.mp4/) }
    2 + chapter_conversions
  end

  def prepare_progress_stage(start_percent, end_percent, command_count)
    @progress_stage_start = start_percent.to_f
    @progress_stage_end = end_percent.to_f
    @progress_stage_command_count = [command_count.to_i, 1].max
    @progress_stage_command_index = 0
    persist_progress(start_percent)
  end

  def next_command_progress_range
    command_width = (@progress_stage_end - @progress_stage_start) / @progress_stage_command_count
    range_start = @progress_stage_start + (command_width * @progress_stage_command_index)
    range_end = [range_start + command_width, @progress_stage_end].min
    @progress_stage_command_index += 1
    [range_start, range_end]
  end

  # All FFmpeg calls in this service pass through this method. FFmpeg reports the
  # media timestamp it has processed, allowing the UI to display measured progress
  # inside long-running encoding commands instead of advancing on a timer.
  def system(command)
    normalized_command = command.to_s.strip
    return Kernel.system(command) unless normalized_command.start_with?("ffmpeg ", "ffmpeg-concat ")

    range_start, range_end = next_command_progress_range

    unless normalized_command.start_with?("ffmpeg ")
      result = Kernel.system(command)
      persist_progress(range_end) if result
      return result
    end

    run_ffmpeg_with_progress(command, range_start, range_end)
  end

  def run_ffmpeg_with_progress(command, range_start, range_end)
    expected_duration = ffmpeg_expected_duration(command)
    progress_command = command.sub(/\bffmpeg\b/, "ffmpeg -progress pipe:1 -nostats")
    stderr_tail = []
    success = false

    Open3.popen3(progress_command) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      stderr_reader = Thread.new do
        stderr.each_line do |line|
          stderr_tail << line
          stderr_tail.shift while stderr_tail.length > 30
        end
      end

      stdout.each_line do |line|
        key, value = line.strip.split("=", 2)
        next unless %w[out_time_us out_time_ms].include?(key)
        next unless expected_duration&.positive?

        processed_seconds = value.to_f / 1_000_000
        ratio = [[processed_seconds / expected_duration, 0].max, 1].min
        persist_progress(range_start + ((range_end - range_start) * ratio))
      end

      stderr_reader.join
      success = wait_thread.value.success?
    end

    if success
      persist_progress(range_end)
    else
      Rails.logger.error("FFmpeg command failed:\n#{stderr_tail.join}")
    end

    success
  rescue StandardError => e
    Rails.logger.error("Unable to track FFmpeg progress: #{e.message}")
    false
  end

  def ffmpeg_expected_duration(command)
    command_tokens = Shellwords.split(command.gsub(/\s+/, " "))
    duration_index = command_tokens.index("-t")
    return parse_ffmpeg_duration(command_tokens[duration_index + 1]) if duration_index

    input_index = command_tokens.index("-i")
    return if input_index.nil?

    input = command_tokens[input_index + 1]
    return concat_input_duration(input.delete_prefix("concat:")) if input.start_with?("concat:")
    return concat_file_duration(input) if command_tokens.each_cons(2).any? { |left, right| left == "-f" && right == "concat" }

    probe_duration(input)
  rescue ArgumentError
    nil
  end

  def parse_ffmpeg_duration(value)
    return value.to_f unless value.include?(":")

    value.split(":").map(&:to_f).reverse.each_with_index.sum { |part, index| part * (60**index) }
  end

  def concat_input_duration(input)
    input.split("|").sum { |path| probe_duration(path).to_f }
  end

  def concat_file_duration(path)
    return unless File.exist?(path)

    File.readlines(path).sum do |line|
      media_path = line[/\Afile\s+['\"]?(.+?)['\"]?\s*\z/, 1]
      media_path ? probe_duration(media_path).to_f : 0
    end
  end

  def probe_duration(path)
    stdout, status = Open3.capture2(
      "ffprobe", "-v", "error", "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1", path.to_s
    )
    return unless status.success?

    duration = stdout.strip.to_f
    duration if duration.positive?
  end

  def persist_progress(value)
    progress = [[value.to_i, 0].max, 99].min
    @last_persisted_progress ||= @video.processing_progress.to_i
    return if progress <= @last_persisted_progress

    @video.update_columns(processing_progress: progress, updated_at: Time.current)
    @last_persisted_progress = progress
  end

  def time_to_seconds(time_str)
    parts = time_str.split(":").map(&:to_f)
    hours = parts[0]
    minutes = parts[1]
    seconds = parts[2]
    hours * 3600 + minutes * 60 + seconds
  end

  def format_time(seconds)
    Time.at(seconds).utc.strftime("%H:%M:%S.%3N")
  end

  def set_final_video_length(final_video_path)
    output = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{final_video_path.to_s.shellescape}`

    raise "Error: Could not retrieve video duration." if output.strip.empty?

    seconds = output.strip.to_f
    formatted_duration = Time.at(seconds).utc.strftime("%H:%M:%S.%3N")

    @video_length = formatted_duration
  end

  def add_to_mlt(input_path, id)
    @mlt_content << <<-MLT
      <producer id="#{id}">
        <property name="resource">#{input_path}</property>
      </producer>
    MLT
  end

  def calculate_chapter_durations
    main_bin_section = @mlt_content[%r{<playlist id="main_bin">(.*?)</playlist>}m, 1]
    chapter_durations = Hash.new(0)

    main_bin_section.scan(/<entry producer="(chapter_intro_\d+|video_\d+_\d+|photo_\d+_\d+)" in="[\d:.]+" out="([\d:.]+)"/).each do |producer, out_time|
      chapter_index = producer.match(/\d+/)[0].to_i
      chapter_durations[chapter_index] += time_to_seconds(out_time)
    end

    chapter_durations.transform_values { |total_seconds| format_time(total_seconds) }
  end

  def duration_to_seconds(duration)
    h, m, s = duration.split(":").map(&:to_f)
    (h * 3600) + (m * 60) + s
  end

  def seconds_to_duration(seconds)
    Time.at(seconds).utc.strftime("%H:%M:%S.%3N")
  end

  def create_combined_music_playlist(chapter_durations)
    entries = chapter_durations.map do |index, duration|
      %(<entry producer="music_#{index}" in="00:00:00.000" out="#{duration}"/>)
    end

    total_blank_seconds = duration_to_seconds(@previews_duration) + duration_to_seconds(@introduction_duration)
    total_blank_duration = seconds_to_duration(total_blank_seconds)

    <<-MLT
    <playlist id="playlist1">
      <property name="shotcut:audio">1</property>
      <property name="shotcut:name">A1</property>
      <blank length="#{total_blank_duration}"/>
      #{entries.join("\n    ")}
    </playlist>
    MLT
  end

  def create_music_playlist
    <<-MLT
    <playlist id="playlist1">
      <property name="shotcut:audio">1</property>
      <property name="shotcut:name">A1</property>
      <entry producer="music_whole_video" in="00:00:00.000" out="#{@video_length}"/>
    </playlist>
    MLT
  end

  def finalize_mlt
    producers = @mlt_content.scan(/<producer id="([^"]+)" in="([^"]+)" out="([^"]+)">/)

    all_playlist_entries = producers.map do |id, in_time, out_time|
      %(<entry producer="#{id}" in="00:00:00.000" out="#{out_time}"/>)
    end

    playlist_entries = producers.reject do |id, _, _|
      id.start_with?("music")
    end.map { |id, _, out_time| %(<entry producer="#{id}" in="00:00:00.000" out="#{out_time}"/>) }

    @mlt_content << <<-MLT
      <producer id="black" in="00:00:00.000" out="#{@video_length}">
        <property name="length">#{@video_length}</property>
        <property name="eof">pause</property>
        <property name="resource">0</property>
        <property name="aspect_ratio">1</property>
        <property name="mlt_service">color</property>
        <property name="mlt_image_format">rgba</property>
        <property name="set.test_audio">0</property>
      </producer>

      <playlist id="background">
        <entry producer="black" in="00:00:00.000" out="#{@video_length}"/>
      </playlist>
    MLT

    # Append the playlist to @mlt_content.
    @mlt_content << <<-MLT
      <playlist id="main_bin">
        <property name="shotcut:skipConvert">0</property>
        <property name="xml_retain">1</property>
        #{all_playlist_entries.join("\n      ")}
      </playlist>

      <playlist id="playlist0">
        <property name="shotcut:skipConvert">0</property>
        <property name="xml_retain">1</property>
        #{playlist_entries.join("\n      ")}
      </playlist>
    MLT

    @mlt_content << if @video.whole_video?
                      create_music_playlist
                    else
                      create_combined_music_playlist(calculate_chapter_durations)
                    end

    @mlt_content << <<-MLT
      <tractor id="tractor0" title="Shotcut version 24.10.29" in="00:00:00.000" out="#{@video_length}">
        <property name="shotcut">1</property>
        <property name="shotcut:projectAudioChannels">2</property>
        <property name="shotcut:projectFolder">0</property>
        <property name="shotcut:skipConvert">0</property>
        <track producer="background"/>
        <track producer="playlist0"/>
        <track producer="playlist1" hide="video"/>
      </tractor>
    MLT

    @mlt_content << "\n</mlt>"

    mlt_file_path = @temp_dir.join("project.mlt")
    File.write(mlt_file_path, @mlt_content)

    upload_to_archive("project.mlt", mlt_file_path)
  end

  def add_to_mlt_img(input_path, file_name, id, duration)
    video_info = `ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1 #{input_path}`
    width, height = video_info.strip.split("\n").map { |line| line.split("=").last.to_i }

    formatted_duration = Time.at(duration).utc.strftime("%H:%M:%S.%3N")
    creation_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S")

    @mlt_content << <<-MLT
      <producer id="#{id}" in="00:00:00.000" out="#{formatted_duration}">
        <property name="length">#{formatted_duration}</property>
        <property name="eof">pause</property>
        <property name="resource">#{file_name}</property>
        <property name="ttl">1</property>
        <property name="aspect_ratio">1</property>
        <property name="meta.media.progressive">1</property>
        <property name="seekable">1</property>
        <property name="format">1</property>
        <property name="meta.media.width">#{width}</property>
        <property name="meta.media.height">#{height}</property>
        <property name="mlt_service">qimage</property>
        <property name="creation_time">#{creation_time}</property>
        <property name="shotcut:skipConvert">1</property>
        <property name="xml">was here</property>
        <property name="ignore_points">1</property>
      </producer>
    MLT
  end

  def add_to_mlt_video(input_path, file_name, id)
    p "+" * 100 + "add_to_mlt_video duration" + "+" * 100

    video_info = `ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=noprint_wrappers=1 #{input_path}`
    duration = video_info.strip.split("=").last.to_f

    # Convert duration to a proper format (hh:mm:ss.sss)
    formatted_duration = Time.at(duration).utc.strftime("%H:%M:%S.%3N")
    p "*" * 100
    p video_info
    p "*" * 100
    p "-" * 100 + "add_to_mlt_video duration" + "-" * 100

    # Get video width and height
    video_dimensions = `ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=noprint_wrappers=1 #{input_path}`
    width, height = video_dimensions.strip.split("\n").map { |line| line.split("=").last.to_i }

    # Get creation time (can be extracted from video or use current time)
    creation_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S")

    @mlt_content << <<-MLT
      <producer id="#{id}" in="00:00:00.000" out="#{formatted_duration}">
        <property name="length">#{formatted_duration}</property>
        <property name="eof">pause</property>
        <property name="resource">#{file_name}</property>
        <property name="ttl">1</property>
        <property name="aspect_ratio">1</property>
        <property name="meta.media.progressive">1</property>
        <property name="seekable">1</property>
        <property name="format">1</property>
        <property name="meta.media.width">#{width}</property>
        <property name="meta.media.height">#{height}</property>
        <property name="mlt_service">avformat-novalidate</property>
        <property name="creation_time">#{creation_time}</property>
        <property name="shotcut:skipConvert">1</property>
        <property name="xml">was here</property>
        <property name="ignore_points">1</property>
      </producer>
    MLT
  end

  def add_to_mlt_music(input_path, file_name, id)
    # Use ffprobe to get the duration of the audio
    p "+" * 100 + "add_to_mlt_music duration" + "+" * 100

    audio_info = `ffprobe -v error -select_streams a:0 -show_entries format=duration -of default=noprint_wrappers=1 #{input_path}`
    duration = audio_info.strip.split("=").last.to_f

    # Convert duration to a proper format (hh:mm:ss.sss)
    formatted_duration = Time.at(duration).utc.strftime("%H:%M:%S.%3N")
    p "*" * 100
    p audio_info
    p "*" * 100
    p "-" * 100 + "add_to_mlt_music duration" + "-" * 100

    # Get audio properties (like sample rate and channels)
    sample_rate_info = `ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate,channels -of default=noprint_wrappers=1 #{input_path}`
    sample_rate, channels = sample_rate_info.strip.split("\n").map { |line| line.split("=").last.to_i }

    # Set creation time (use current time)
    creation_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S")

    @mlt_content << <<-MLT
      <producer id="#{id}" in="00:00:00.000" out="#{formatted_duration}">
        <property name="length">#{formatted_duration}</property>
        <property name="eof">pause</property>
        <property name="resource">#{file_name}</property>
        <property name="mlt_service">avformat-novalidate</property>
        <property name="meta.media.nb_streams">1</property>
        <property name="meta.media.0.stream.type">audio</property>
        <property name="meta.media.0.codec.sample_rate">#{sample_rate}</property>
        <property name="meta.media.0.codec.channels">#{channels}</property>
        <property name="meta.media.0.codec.layout">#{channels == 2 ? 'stereo' : 'mono'}</property>
        <property name="creation_time">#{creation_time}</property>
        <property name="seekable">1</property>
        <property name="audio_index">0</property>
        <property name="video_index">-1</property>
        <property name="shotcut:skipConvert">1</property>
        <property name="ignore_points">0</property>
        <property name="shotcut:caption">#{File.basename(file_name)}</property>
      </producer>
    MLT
  end

  def upload_to_archive(file_name, path)
    Zip::File.open(@archive_path, Zip::File::CREATE) do |zip|
      zip.add(file_name, path)
    end
  end
end
