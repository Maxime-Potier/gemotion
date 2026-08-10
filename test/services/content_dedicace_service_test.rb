require "test_helper"

class ContentDedicaceServiceTest < ActiveSupport::TestCase
  test "photo video filter preserves the original aspect ratio" do
    filter = ContentDedicaceService::LANDSCAPE_IMAGE_FILTER

    assert_includes filter, "force_original_aspect_ratio=decrease"
    assert_includes filter, "pad=1280:720"
    assert_includes filter, "setsar=1"
  end
end
