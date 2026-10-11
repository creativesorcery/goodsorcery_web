require "test_helper"

class ChartHelperTest < ActionView::TestCase
  include ChartHelper

  test "sparkline draws an area, a line and an end dot scaled to the max" do
    svg = parse(sparkline_svg([ 0, 5, 10 ], color: ChartHelper::CORAL))

    assert_equal "120", svg["width"]
    assert_equal "28", svg["height"]
    assert_equal "0 0 120 28", svg["viewBox"]
    area, line = svg.css("path")
    assert_equal "0.18", area["fill-opacity"]
    assert_equal "M0,26 L60,14 L120,2", line["d"]
    dot = svg.at_css("circle")
    assert_equal [ "120", "2" ], [ dot["cx"], dot["cy"] ]
  end

  test "sparkline copes with empty and single-value series" do
    assert_equal "M0,26 L120,26", parse(sparkline_svg([], color: ChartHelper::IRIS)).css("path")[1]["d"]
    assert_equal "M0,2 L120,2", parse(sparkline_svg([ 7 ], color: ChartHelper::IRIS)).css("path")[1]["d"]
  end

  test "stacked sparkline stacks each layer on the ones below, scaled to the largest total" do
    svg = parse(stacked_sparkline_svg([ { values: [ 0, 5, 10 ], color: ChartHelper::CORAL },
                                        { values: [ 0, 5, 0 ], color: ChartHelper::LILAC } ]))

    bottom_area, bottom_line, top_area, top_line = svg.css("path")
    assert_equal "M0,26 L60,14 L120,2 L120,28 L0,28 Z", bottom_area["d"]
    assert_equal [ ChartHelper::CORAL, "M0,26 L60,14 L120,2" ], [ bottom_line["stroke"], bottom_line["d"] ]
    assert_equal "M0,26 L60,2 L120,2 L120,2 L60,14 L0,26 Z", top_area["d"]
    assert_equal [ ChartHelper::LILAC, "M0,26 L60,2 L120,2" ], [ top_line["stroke"], top_line["d"] ]
    dot = svg.at_css("circle")
    assert_equal [ "120", "2", ChartHelper::LILAC ], [ dot["cx"], dot["cy"], dot["fill"] ]
    assert_equal "true", svg["aria-hidden"]
  end

  test "a one-layer stacked sparkline is a plain area in that colour" do
    svg = parse(stacked_sparkline_svg([ { values: [ 0, 0, 0 ], color: ChartHelper::IRIS } ], width: 140, height: 44))

    assert_equal 2, svg.css("path").size
    assert_equal "M0,42 L70,42 L140,42", svg.css("path")[1]["d"]
  end

  test "fluid charts stretch to their container" do
    svg = parse(sparkline_svg([ 1, 2 ], color: ChartHelper::MINT, width: 140, height: 44, fluid: true))

    assert_equal "100%", svg["width"]
    assert_equal "none", svg["preserveAspectRatio"]
    assert_equal "0 0 140 44", svg["viewBox"]
  end

  test "histogram draws one titled bar per value with a minimum height" do
    svg = parse(histogram_svg([ 0, 1284, 2 ], color: ChartHelper::IRIS_SOFT))
    bars = svg.css("rect")

    assert_equal 3, bars.size
    assert_equal [ "0", "1,284", "2" ], bars.map { |bar| bar.at_css("title").text }
    assert_equal "1.5", bars.first["height"]
    assert_equal "28", bars[1]["height"]
    assert_equal [ "0.8" ], bars.map { |bar| bar["opacity"] }.uniq
  end

  test "histogram highlights the last bucket and accepts custom titles" do
    svg = parse(histogram_svg([ 3, 4 ], color: ChartHelper::CORAL, highlight_last: true, titles: [ "09:00 · 3", "10:00 · 4" ]))

    assert_equal [ "0.8", "1" ], svg.css("rect").map { |bar| bar["opacity"] }
    assert_equal "10:00 · 4", svg.css("rect title").last.text
  end

  test "histogram bar geometry follows the slot width" do
    bar = parse(histogram_svg([ 1, 1 ], color: ChartHelper::CORAL, width: 150, height: 30)).css("rect").last

    assert_equal [ "76", "73", "2", "28" ], [ bar["x"], bar["width"], bar["y"], bar["height"] ]
  end

  test "stacked bar lays segments out in percentages with 1px gaps" do
    svg = parse(stacked_bar_svg([ { share: 0.94, color: ChartHelper::CORAL }, { share: 0.06, color: ChartHelper::IRIS, opacity: 0.5, title: "other" } ]))
    track, first, second, gap = svg.css("rect")

    assert_equal "100%", track["width"]
    assert_equal [ "0%", "94%" ], [ first["x"], first["width"] ]
    assert_equal [ "94%", "6%", "0.5" ], [ second["x"], second["width"], second["opacity"] ]
    assert_equal "other", second.at_css("title").text
    assert_equal [ "94%", "1" ], [ gap["x"], gap["width"] ]
  end

  test "meter fills by fraction and turns coral near the quota" do
    calm = parse(meter_svg(0.41)).css("rect").last
    hot = parse(meter_svg(0.95)).css("rect").last

    assert_equal [ "41%", ChartHelper::METER ], [ calm["width"], calm["fill"] ]
    assert_equal ChartHelper::CORAL, hot["fill"]
    assert_equal "100%", parse(meter_svg(3)).css("rect").last["width"]
    assert_equal "0%", parse(meter_svg(nil)).css("rect").last["width"]
  end

  test "charts never use inline styles" do
    output = [ sparkline_svg([ 1 ], color: ChartHelper::IRIS), histogram_svg([ 1 ], color: ChartHelper::IRIS),
               stacked_bar_svg([ { share: 1, color: ChartHelper::MINT } ]), meter_svg(0.5),
               stacked_sparkline_svg([ { values: [ 1, 2 ], color: ChartHelper::CORAL } ]) ].join

    assert_no_match(/style=/, output)
  end

  private
    def parse(html)
      Nokogiri::XML(html.to_s).root
    end
end
