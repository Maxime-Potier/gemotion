require "test_helper"

class FinalCutProExportServiceTest < ActiveSupport::TestCase
  setup do
    @temp_dir = Pathname(Dir.mktmpdir)
    @first_clip = @temp_dir.join("first clip.mov")
    @second_clip = @temp_dir.join("second.mp4")
    @first_clip.write("first")
    @second_clip.write("second")
    @video = Struct.new(:id).new(42)
    @probe = lambda do |path|
      {
        duration: path == @first_clip ? 2.0 : 1.5,
        width: 1280,
        height: 720,
        has_audio: true,
        audio_channels: 2,
        audio_rate: 48_000
      }
    end
  end

  teardown do
    FileUtils.rm_rf(@temp_dir)
  end

  test "creates a portable FCPXML 1.14 bundle with an editable timeline" do
    archive = FinalCutProExportService.new(
      video: @video,
      media_paths: [@first_clip, @second_clip],
      output_dir: @temp_dir,
      probe: @probe
    ).call

    Zip::File.open(archive) do |zip|
      root = "GeMotion-42.fcpxmld"
      assert zip.find_entry("#{root}/Media/001_first_clip.mov")
      assert zip.find_entry("#{root}/Media/002_second.mp4")

      xml = Nokogiri::XML(zip.read("#{root}/Info.fcpxml")) { |config| config.strict }
      assert_equal "fcpxml", xml.internal_subset.name
      assert_equal "1.14", xml.at_xpath("/fcpxml")["version"]
      assert_equal "105/30s", xml.at_xpath("//sequence")["duration"]
      assert_equal 2, xml.xpath("//asset").count
      assert_equal 2, xml.xpath("//spine/asset-clip").count
      assert_equal 2, xml.xpath("//event/asset-clip").count
      assert_equal "./Media/001_first_clip.mov", xml.at_xpath("//asset/media-rep")["src"]
      assert_equal "60/30s", xml.xpath("//spine/asset-clip").last["offset"]
    end
  end

  test "ignores missing media and rejects an empty export" do
    assert_raises(ArgumentError) do
      FinalCutProExportService.new(
        video: @video,
        media_paths: [@temp_dir.join("missing.mov")],
        output_dir: @temp_dir,
        probe: @probe
      ).call
    end
  end

  test "losslessly remuxes generated transport streams to MOV" do
    transport_stream = @temp_dir.join("generated.ts")
    assert system(
      "ffmpeg", "-loglevel", "error", "-y",
      "-f", "lavfi", "-i", "color=c=blue:s=320x180:r=30",
      "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
      "-t", "0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
      "-f", "mpegts", transport_stream.to_s
    )

    archive = FinalCutProExportService.new(
      video: @video,
      media_paths: [transport_stream],
      output_dir: @temp_dir
    ).call

    Zip::File.open(archive) do |zip|
      root = "GeMotion-42.fcpxmld"
      assert zip.find_entry("#{root}/Media/001_fcpxml_42_001.mov")
      xml = Nokogiri::XML(zip.read("#{root}/Info.fcpxml"))
      assert_equal "./Media/001_fcpxml_42_001.mov", xml.at_xpath("//media-rep")["src"]
    end
    assert_not @temp_dir.join("fcpxml_42_001.mov").exist?
  end
end
