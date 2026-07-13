require "json"
require "open3"
require "zip"

class FinalCutProExportService
  FCPXML_VERSION = "1.14"
  FRAME_RATE = 30

  Media = Data.define(:path, :filename, :name, :duration_frames, :width, :height,
                      :has_audio, :audio_channels, :audio_rate)

  def initialize(video:, media_paths:, output_dir:, probe: nil)
    @video = video
    @media_paths = media_paths
    @output_dir = Pathname(output_dir)
    @probe = probe || method(:probe_media)
  end

  def call
    FileUtils.mkdir_p(@output_dir)
    @temporary_media = []
    media = build_media
    raise ArgumentError, "No media is available for the Final Cut Pro export" if media.empty?

    archive_path = @output_dir.join("final_cut_pro_#{@video.id}.zip")
    bundle_name = "GeMotion-#{@video.id}.fcpxmld"

    FileUtils.rm_f(archive_path)
    Zip::File.open(archive_path, create: true) do |zip|
      zip.get_output_stream("#{bundle_name}/Info.fcpxml") { |io| io.write(build_fcpxml(media)) }
      media.each do |item|
        zip.add("#{bundle_name}/Media/#{item.filename}", item.path)
      end
    end

    archive_path
  ensure
    Array(@temporary_media).each { |path| FileUtils.rm_f(path) }
  end

  private

  def build_media
    Array(@media_paths).filter_map.with_index do |path, index|
      path = Pathname(path)
      next unless path.file? && path.size.positive?

      path = normalize_media(path, index)

      metadata = @probe.call(path)
      next unless metadata && metadata[:duration].to_f.positive?

      extension = path.extname.downcase.presence || ".mov"
      basename = ActiveSupport::Inflector.transliterate(path.basename(extension).to_s)
      basename = basename.gsub(/[^a-zA-Z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
      basename = "clip" if basename.blank?

      Media.new(
        path: path,
        filename: format("%03d_%s%s", index + 1, basename, extension),
        name: basename.tr("_", " "),
        duration_frames: [(metadata[:duration].to_f * FRAME_RATE).round, 1].max,
        width: metadata[:width].to_i.positive? ? metadata[:width].to_i : 1920,
        height: metadata[:height].to_i.positive? ? metadata[:height].to_i : 1080,
        has_audio: metadata[:has_audio] == true,
        audio_channels: metadata[:audio_channels].to_i.positive? ? metadata[:audio_channels].to_i : 2,
        audio_rate: metadata[:audio_rate].to_i.positive? ? metadata[:audio_rate].to_i : 48_000
      )
    end
  end

  def normalize_media(path, index)
    return path unless path.extname.casecmp?(".ts")

    output_path = @output_dir.join(format("fcpxml_%s_%03d.mov", @video.id, index + 1))
    _stdout, stderr, status = Open3.capture3(
      "ffmpeg", "-loglevel", "error", "-y", "-i", path.to_s,
      "-map", "0:v:0", "-map", "0:a?", "-c", "copy", "-movflags", "+faststart",
      output_path.to_s
    )
    raise "Unable to prepare #{path.basename} for Final Cut Pro: #{stderr.strip}" unless status.success?

    @temporary_media << output_path
    output_path
  end

  def build_fcpxml(media)
    total_frames = media.sum(&:duration_frames)
    width = media.first.width
    height = media.first.height

    builder = Nokogiri::XML::Builder.new do |xml|
      xml.fcpxml(version: FCPXML_VERSION) do
        xml.resources do
          xml.format(
            id: "r1",
            name: "FFVideoFormat#{height}p#{FRAME_RATE}",
            frameDuration: frame_time(1),
            width: width,
            height: height,
            colorSpace: "1-1-1 (Rec. 709)"
          )

          media.each_with_index do |item, index|
            attributes = {
              id: "r#{index + 2}",
              name: item.name,
              start: "0s",
              duration: frame_time(item.duration_frames),
              hasVideo: "1",
              format: "r1"
            }
            if item.has_audio
              attributes.merge!(
                hasAudio: "1",
                audioSources: "1",
                audioChannels: item.audio_channels,
                audioRate: item.audio_rate
              )
            end

            xml.asset(attributes) do
              xml.send(
                "media-rep",
                kind: "original-media",
                src: "./Media/#{item.filename}",
                suggestedFilename: item.name
              )
            end
          end
        end

        xml.library do
          xml.event(name: "GeMotion") do
            xml.project(name: "GeMotion video #{@video.id}") do
              xml.sequence(
                format: "r1",
                duration: frame_time(total_frames),
                tcStart: "0s",
                tcFormat: "NDF",
                audioLayout: "stereo",
                audioRate: "48k"
              ) do
                xml.spine do
                  offset_frames = 0
                  media.each_with_index do |item, index|
                    xml.send(
                      "asset-clip",
                      ref: "r#{index + 2}",
                      name: item.name,
                      offset: frame_time(offset_frames),
                      start: "0s",
                      duration: frame_time(item.duration_frames)
                    )
                    offset_frames += item.duration_frames
                  end
                end
              end
            end

            media.each_with_index do |item, index|
              clip_attributes = {
                ref: "r#{index + 2}",
                name: item.name,
                format: "r1",
                start: "0s",
                duration: frame_time(item.duration_frames)
              }
              clip_attributes[:audioRole] = "dialogue" if item.has_audio
              xml.send("asset-clip", clip_attributes)
            end
          end
        end
      end
    end

    xml_body = builder.doc.root.to_xml
    %(<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE fcpxml>\n#{xml_body}\n)
  end

  def frame_time(frames)
    return "0s" if frames.zero?

    "#{frames}/#{FRAME_RATE}s"
  end

  def probe_media(path)
    stdout, status = Open3.capture2(
      "ffprobe", "-v", "error", "-show_entries",
      "format=duration:stream=codec_type,width,height,channels,sample_rate",
      "-of", "json", path.to_s
    )
    return unless status.success?

    data = JSON.parse(stdout, symbolize_names: true)
    video_stream = data.fetch(:streams, []).find { |stream| stream[:codec_type] == "video" }
    audio_stream = data.fetch(:streams, []).find { |stream| stream[:codec_type] == "audio" }

    {
      duration: data.dig(:format, :duration).to_f,
      width: video_stream&.dig(:width),
      height: video_stream&.dig(:height),
      has_audio: audio_stream.present?,
      audio_channels: audio_stream&.dig(:channels),
      audio_rate: audio_stream&.dig(:sample_rate)
    }
  rescue JSON::ParserError
    nil
  end
end
