require "test_helper"

class PerformanceChartHelperTest < ActionView::TestCase
  include ApmFixtureClock

  include PerformanceChartHelper, PerformanceHelper, ChartHelper, ::NumberHelper

  Bin = Apm::Overview::Bin

  test "the timeline axis keeps its units lowercase inside the uppercase header" do
    svg = Nokogiri::HTML5.fragment(apm_axis_svg([ [ 0, 0.0 ], [ 1000, 0.5 ], [ 2000, 1.0 ] ])).at_css("svg")

    assert_includes svg["class"].split, "normal-case"
    assert_equal [ "0", "1 s", "2 s" ], svg.css("text").map(&:text)
  end

  test "axis tops are round and hold every value" do
    assert_equal 600, apm_axis_max([ 120, 590, nil ])
    assert_equal 3000, apm_axis_max([ 2180 ])
    assert_equal 7.5, apm_axis_max([ 7 ])
    assert_equal [ 600, 400, 200, 0 ], apm_y_ticks(600)
  end

  test "layer bars stack bottom-up app code, database, HTTP, rendering with a title per bin and the p95 line" do
    time = Time.utc(2026, 11, 4, 14)
    bins = [ Bin.new(time:, split: { db: 40.0, http: 20.0, view: 10.0, app: 30.0 }, average_ms: 100.0, p95: 300.0),
             Bin.new(time: time + 15.minutes, split: nil, average_ms: nil, p95: nil),
             Bin.new(time: time + 30.minutes, split: { db: 10.0, http: 0.0, view: 0.0, app: 10.0 }, average_ms: 20.0, p95: 150.0) ]
    svg = Nokogiri::HTML5.fragment(apm_layer_bars_svg(bins, max: 600, label: "Average time")).at_css("svg")

    assert_equal "Average time", svg["aria-label"]
    assert_equal 2, svg.css("g").size
    fills = svg.css("g").first.css("rect").map { it["fill"] }
    assert_equal [ PerformanceChartHelper::APP_CODE, PerformanceChartHelper::LILAC, PerformanceChartHelper::IRIS, PerformanceChartHelper::MINT_400 ], fills
    assert_match(/average 100 ms · p95 300 ms/, svg.at_css("g title").text)
    line = svg.css("path").find { it["stroke"] == PerformanceChartHelper::CORAL }
    assert_equal 2, line["d"].scan("M").size, "a gap breaks the p95 line"
  end

  test "five lines with the average dashed" do
    lines = { average: [ 100, 110 ], 75 => [ 120, 130 ], 90 => [ 200, nil ], 95 => [ 300, 320 ], 99 => [ 500, 520 ] }
    svg = Nokogiri::HTML5.fragment(apm_lines_svg(lines, max: 600, label: "Lines")).at_css("svg")

    paths = svg.css("path[fill=none]")
    assert_equal 5, paths.size
    assert_equal [ "5 4" ], paths.filter_map { it["stroke-dasharray"] }
    assert_equal PerformanceChartHelper::INK, paths.last["stroke"]
  end

  test "a split bar draws its layers in legend order inside a clipped length" do
    svg = Nokogiri::HTML5.fragment(apm_split_bar_svg({ db: 50.0, http: 25.0, view: 0.0, app: 25.0 }, scale_ms: 200.0, title: "t")).at_css("svg")

    assert_equal "50%", svg.at_css("clipPath rect")["width"]
    segments = svg.css("g rect")
    assert_equal [ PerformanceChartHelper::LILAC, PerformanceChartHelper::IRIS, PerformanceChartHelper::APP_CODE ], segments.map { it["fill"] }
    assert_equal [ "0%", "25%", "37.5%" ], segments.map { it["x"] }
  end

  test "timeline bars stay inside the row" do
    svg = Nokogiri::HTML5.fragment(apm_timeline_bar_svg(2560, 320, 900, color: "#000", ticks: [ [ 0, 0.0 ], [ 500, 0.5 ] ])).at_css("svg")
    bar = svg.css("rect").last

    assert_equal "100%", bar["x"]
    assert_equal 3, svg.css("rect").size
  end

  test "the p95 sparkline fills gaps and is coral when slower" do
    svg = Nokogiri::HTML5.fragment(apm_p95_sparkline([ nil, 100.0, nil, 300.0 ], slower: true)).at_css("svg")
    assert_equal ChartHelper::CORAL, svg.at_css("circle")["fill"]
    assert_nil apm_p95_sparkline([ nil, nil ], slower: false)
  end

  test "x labels per range" do
    assert_equal %w[−24h −18h −12h −6h now], apm_x_labels(Apm::Range.new("1d"))
  end
end
