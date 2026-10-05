require "test_helper"

class CapturedDataHelperTest < ActionView::TestCase
  test "pretty_json colours strings and numbers and mutes filtered values, nested too" do
    html = pretty_json({ "note" => 'say "hi" <b>', "n" => 3, "ok" => true, "cards" => [ "[FILTERED]", { "token" => "[FILTERED]" } ] })
    doc = Nokogiri::HTML5.fragment(html)

    assert_equal [ "\"note\"", "\"say \\\"hi\\\" <b>\"", "\"n\"", "\"ok\"", "\"cards\"", "\"token\"" ], doc.css("span.tok-s").map(&:text)
    assert_equal [ "3", "true" ], doc.css("span.tok-n").map(&:text)
    assert_equal [ "[FILTERED]", "[FILTERED]" ], doc.css("span.text-ink-400").map(&:text)
    assert_not_includes html, "<b>", "captured markup is escaped"
  end

  test "context_value mutes filtered values and serialises structures" do
    assert_includes context_value("[FILTERED]"), "text-ink-400"
    assert_includes context_value("x", tone: "text-mint-300"), "text-mint-300"
    assert_equal '{"a":[1]}', context_text({ "a" => [ 1 ] })
    assert_equal "", context_text(nil)
  end
end
