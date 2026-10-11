# Server-rendered SVG charts (no chart JS, no inline styles: CSP-safe). Geometry
# matches design/assets/theme.js. Only numbers ever reach these helpers.
module ChartHelper
  CORAL = "#ef6f7c".freeze
  IRIS = "#8f94ee".freeze
  IRIS_SOFT = "#b7baf3".freeze
  IRIS_DEEP = "#6f75e0".freeze
  LILAC = "#b39cf2".freeze
  MINT = "#5cc29a".freeze
  PAPER = "#b5b1a7".freeze
  TRACK = "#e7e5df".freeze
  TRACK_SOFT = "#efeee9".freeze
  METER = "#7f85ea".freeze
  GAP = "#ffffff".freeze

  # Area + 2px line + end dot. Values are scaled to the series max.
  def sparkline_svg(values, color:, width: 120, height: 28, fluid: false)
    points = sparkline_points(values, width, height)
    line = svg_line(points)
    shapes = [
      tag.path(d: "#{line} L#{width},#{height} L0,#{height} Z", fill: color, "fill-opacity": 0.18),
      sparkline_stroke(line, color, 2),
      sparkline_dot(points.last, color)
    ]
    chart_svg(safe_join(shapes), width, height, fluid:, "aria-hidden": true)
  end

  # Stacked sparkline: layers are [{ values:, color: }], bottom first, all the
  # same length. Each layer is an area on top of the ones below with its own
  # line, scaled to the largest total; the dot marks the latest total.
  def stacked_sparkline_svg(layers, width: 120, height: 28)
    tops = stacked_totals(layers.map { |layer| Array(layer[:values]) })
    scale = { width:, height:, max: tops.last.max }
    shapes = layers.each_with_index.flat_map do |layer, index|
      stacked_layer(tops[index], (tops[index - 1] if index.positive?), layer[:color], scale)
    end
    shapes << sparkline_dot(sparkline_points(tops.last, width, height, max: scale[:max]).last, layers.last[:color])
    chart_svg(safe_join(shapes), width, height, fluid: false, "aria-hidden": true)
  end

  # One bar per value (opacity 0.8; the last bar at 1.0 when highlighted), each with a <title>.
  def histogram_svg(values, color:, width: 150, height: 30, highlight_last: false, fluid: false, titles: nil)
    values = Array(values)
    scale = { slot: width.fdiv([ values.size, 1 ].max), max: [ values.max.to_f, 1 ].max, height: }
    bars = values.each_with_index.map do |value, index|
      opacity = highlight_last && index == values.size - 1 ? 1 : 0.8
      histogram_bar(value, index, scale, fill: color, opacity:, title: titles&.at(index) || number_with_delimiter(value))
    end
    chart_svg(safe_join(bars), width, height, fluid:, role: "img")
  end

  # Horizontal share bar: segments are [{ share: 0..1, color:, opacity: 1, title: nil }].
  def stacked_bar_svg(segments, height: 8)
    offsets = segments.each_with_object([ 0.0 ]) { |segment, sums| sums << sums.last + segment_share(segment) }
    shapes = [ tag.rect(width: "100%", height:, fill: TRACK_SOFT) ]
    shapes += segments.each_with_index.map { |segment, i| stacked_segment(segment, offsets[i], height) }
    shapes += offsets[1...-1].map { |offset| tag.rect(x: percent(offset), width: 1, height:, fill: GAP) }
    tag.svg safe_join(shapes), width: "100%", height:, class: "block w-full rounded-full overflow-hidden", role: "img"
  end

  # Quota meter: iris normally, coral from 90% used.
  def meter_svg(fraction, height: 6)
    fraction = fraction.to_f.clamp(0, 1)
    fill = fraction >= 0.9 ? CORAL : METER
    shapes = [ tag.rect(width: "100%", height:, fill: TRACK), tag.rect(width: percent(fraction), height:, rx: height / 2.0, fill:) ]
    tag.svg safe_join(shapes), width: "100%", height:, class: "block w-full rounded-full overflow-hidden",
      role: "img", "aria-label": "#{(fraction * 100).round}% used"
  end

  private
    def chart_svg(content, width, height, fluid:, **attributes)
      size = fluid ? { width: "100%", preserveAspectRatio: "none" } : { width: }
      tag.svg content, **size, height:, viewBox: "0 0 #{width} #{height}", class: "block overflow-visible", **attributes
    end

    def sparkline_points(values, width, height, max: nil)
      values = Array(values).map(&:to_f).presence || [ 0.0 ]
      values *= 2 if values.one?
      max = [ max || values.max, 1 ].max
      step = width.fdiv(values.size - 1)
      values.each_with_index.map { |value, i| [ i * step, height - 2 - (value / max) * (height - 4) ] }
    end

    def svg_line(points, start: "M")
      points.each_with_index.map { |(x, y), i| "#{i.zero? ? start : 'L'}#{svg_number(x)},#{svg_number(y)}" }.join(" ")
    end

    def sparkline_stroke(line, color, width)
      tag.path d: line, fill: "none", stroke: color, "stroke-width": width, "stroke-linejoin": "round", "stroke-linecap": "round"
    end

    def sparkline_dot((x, y), color)
      tag.circle cx: svg_number(x), cy: svg_number(y), r: 3, fill: color
    end

    # Running totals: the top edge of each layer.
    def stacked_totals(series)
      running = Array.new(series.first.size, 0)
      series.map { |values| running = running.zip(values).map(&:sum) }
    end

    # The area between this layer's top and the one below (the chart's floor
    # for the bottom layer), plus a line along its top.
    def stacked_layer(top, below, color, scale)
      width, height, max = scale.values_at(:width, :height, :max)
      line = svg_line(sparkline_points(top, width, height, max:))
      floor = below ? svg_line(sparkline_points(below, width, height, max:).reverse, start: "L") : "L#{width},#{height} L0,#{height}"
      [ tag.path(d: "#{line} #{floor} Z", fill: color, "fill-opacity": 0.22), sparkline_stroke(line, color, 1.5) ]
    end

    def histogram_bar(value, index, scale, fill:, opacity:, title:)
      bar_height = [ 1.5, value.to_f / scale[:max] * (scale[:height] - 2) ].max
      tag.rect tag.title(title), x: svg_number(index * scale[:slot] + 1), y: svg_number(scale[:height] - bar_height),
        width: svg_number([ 1, scale[:slot] - 2 ].max), height: svg_number(bar_height), rx: 1, fill:, opacity:
    end

    def stacked_segment(segment, offset, height)
      title = segment[:title] && tag.title(segment[:title])
      tag.rect title, x: percent(offset), width: percent(segment_share(segment)), height:,
        fill: segment[:color], opacity: segment.fetch(:opacity, 1)
    end

    def segment_share(segment)
      segment[:share].to_f.clamp(0, 1)
    end

    def percent(fraction)
      "#{svg_number(fraction * 100)}%"
    end

    # 1 decimal place, without a trailing ".0".
    def svg_number(number)
      rounded = number.to_f.round(1)
      rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
    end
end
