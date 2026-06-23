require "test_helper"

class MarkdownRendererTest < ActiveSupport::TestCase
  test "renders imported Slack emotes as inline images even when markdown images are disabled" do
    SlackEmoteRegistry.stub(:all, { "stardust" => "https://emoji.slack-edge.com/T123/stardust/abc.png" }) do
      html = MarkdownRenderer.render("hello :stardust: ![nope](https://example.com/nope.png)", allow_images: false)

      assert_includes html, "slack-emote"
      assert_includes html, "https://emoji.slack-edge.com/T123/stardust/abc.png"
      assert_includes html, "alt=\":stardust:\""
      assert_not_includes html, "nope.png"
    end
  end

  test "does not render Slack emotes inside code" do
    SlackEmoteRegistry.stub(:all, { "stardust" => "https://emoji.slack-edge.com/T123/stardust/abc.png" }) do
      html = MarkdownRenderer.render("`:stardust:`", allow_images: false)

      assert_includes html, ":stardust:"
      assert_not_includes html, "slack-emote"
    end
  end
end
