# Server-rendered SVG for the Performance pages (docs/ARCHITECTURE.md §13.9):
# the time-by-layer bars with the p95 line, the five response-time lines,
# horizontal layer-split bars, the trace timeline and its axis. Built with
# tag like ChartHelper: no chart JS, no inline styles, numbers to 1 dp, a
# <title> per bar or bin. Only numbers and times reach these helpers.
module PerformanceChartHelper
  LILAC = "#b39cf2".freeze
  IRIS = "#8f94ee".freeze
  MINT_400 = "#6fcca6".freeze
  RUBY = "#d2cec4".freeze
  INK = "#34374d".freeze
  IRIS_300 = "#5a5fd6".freeze
  CORAL = "#ef6f7c".freeze
  IRIS_SOFT = "#b7baf3".freeze
  GRID = "#efeee9".freeze
  AXIS = "#d7d4cc".freeze

  LAYER_COLORS = { db: LILAC, http: IRIS, view: MINT_400, ruby: RUBY }.freeze
  # Bottom-up stack order of the overview chart (the legend reads db, http, view, ruby).
  STACK_ORDER = %i[ruby db http view].freeze
  LINE_STYLES = {
    average: { stroke: INK, width: 1.6, dash: "5 4" },
    75 => { stroke: IRIS, width: 2 },
    90 => { stroke: IRIS_300, width: 2 },
    95 => { stroke: CORAL, width: 2.4 },
    99 => { stroke: IRIS_SOFT, width: 2 }
  }.freeze
  # Back to front, so the average and p95 stay on top.
  LINE_DRAW_ORDER = [ 99, 95, 90, 75, :average ].freeze
  WIDTH = 960
  HEIGHT = 220
  Y_INTERVALS = 3
  NICE_STEPS = [ 1, 2, 2.5, 5, 10 ].freeze
  # Evenly spaced x labels per range key.
  X_LABELS = {
    "15m" => %w[−15m −10m −5m now],
    "1h" => %w[−1h −45m −30m −15m now],
    "1d" => %w[−24h −18h −12h −6h now],
    "7d" => %w[−7d −6d −5d −4d −3d −2d −1d now],
    "30d" => %w[−30d −24d −18d −12d −6d now]
  }.freeze

  # A round top for a y axis of Y_INTERVALS steps that holds every value.
  def apm_axis_max(values)
    peak = values.compact.max.to_f
    return Y_INTERVALS.to_f unless peak.positive?

    raw = peak / Y_INTERVALS
    scale = 10**Math.log10(raw).floor
    NICE_STEPS.map { it * scale }.find { it >= raw } * Y_INTERVALS
  end

  # Tick values from the top down: [600, 400, 200, 0].
  def apm_y_ticks(max) = Array.new(Y_INTERVALS + 1) { |i| max * (Y_INTERVALS - i) / Y_INTERVALS }

  def apm_x_labels(range) = X_LABELS.fetch(range.key)

  # Stacked layer bars per bin (Apm::Overview::Bin) with the p95 line on top.
  def apm_layer_bars_svg(bins, max:, label:)
    slot = WIDTH.fdiv([ bins.size, 1 ].max)
    shapes = apm_grid_lines + bins.each_with_index.filter_map { |bin, i| apm_bin_group(bin, i, slot, max) }
    shapes << apm_line_path(bins.map(&:p95), slot, max, LINE_STYLES[95].merge(width: 2.2)) << apm_baseline
    apm_chart_svg(shapes, label)
  end

  # Five lines over the bins: { average: [ms|nil], 75 => […], … }.
  def apm_lines_svg(lines, max:, label:)
    slot = WIDTH.fdiv([ lines.values.first.to_a.size, 1 ].max)
    paths = LINE_DRAW_ORDER.map { |key| apm_line_path(lines.fetch(key), slot, max, LINE_STYLES.fetch(key)) }
    apm_chart_svg(apm_grid_lines + paths + [ apm_baseline ], label)
  end

  # One horizontal bar split by layer ({ db:, http:, view:, ruby: } in ms),
  # its length value / scale_ms of the box.
  def apm_split_bar_svg(split, scale_ms:, height: 14, title: nil)
    total = split.values.sum
    return tag.svg(width: "100%", height:, class: "block", "aria-hidden": true) unless total.positive? && scale_ms.positive?

    clip = apm_clip_id
    length = (total / scale_ms).clamp(0.0, 1.0)
    shapes = [ tag.defs(tag.clipPath(tag.rect(width: apm_percent_attr(length), height:, rx: 5), id: clip)) ]
    shapes << tag.g(safe_join(apm_split_segments(split, total, length, height)), "clip-path": "url(##{clip})")
    tag.svg safe_join([ (tag.title(title) if title), *shapes ].compact), width: "100%", height:, class: "block", role: "img"
  end

  # A timeline row's bar: from offset_ms for width_ms of total_ms, over the
  # axis ticks' faint gridlines.
  def apm_timeline_bar_svg(offset_ms, width_ms, total_ms, color:, ticks: [], tall: false)
    total = [ total_ms.to_f, 1 ].max
    x = (offset_ms.to_f / total).clamp(0.0, 1.0)
    width = (width_ms.to_f / total).clamp(0.0025, [ 1.0 - x, 0.0025 ].max)
    grid = ticks.map { |_, fraction| tag.rect(x: apm_percent_attr(fraction), width: 1, height: 16, fill: GRID) }
    bar = tag.rect(x: apm_percent_attr(x), y: tall ? 2 : 3, width: apm_percent_attr(width), height: tall ? 12 : 10, rx: 2, fill: color)
    tag.svg safe_join(grid + [ bar ]), width: "100%", height: 16, class: "block", "aria-hidden": true
  end

  # The timeline's axis labels ([[ms, fraction]]) as SVG text.
  def apm_axis_svg(ticks)
    labels = ticks.each_with_index.map do |(ms, fraction), index|
      tag.text(index.zero? ? "0" : apm_duration(ms), x: apm_percent_attr(fraction), y: 12, "text-anchor": apm_tick_anchor(index, ticks.size))
    end
    tag.svg safe_join(labels), width: "100%", height: 16, class: "block overflow-visible fill-ink-400 font-mono text-[11px]", "aria-hidden": true
  end

  # A 10px legend square in a layer's colour.
  def apm_swatch(layer)
    tag.svg tag.rect(width: 10, height: 10, rx: 3, fill: LAYER_COLORS.fetch(layer)), width: 10, height: 10, viewBox: "0 0 10 10",
      class: "shrink-0", "aria-hidden": true
  end

  # A short legend line in a line's style (dashed for the average).
  def apm_line_swatch(key)
    style = LINE_STYLES.fetch(key)
    line = tag.line(x1: 0, y1: 2, x2: 14, y2: 2, stroke: style[:stroke], "stroke-width": 2, "stroke-dasharray": (style[:dash] && "3 2"))
    tag.svg line, width: 14, height: 4, viewBox: "0 0 14 4", class: "shrink-0", "aria-hidden": true
  end

  # The overview's time share: an 84px track filled to the share (0..1).
  def apm_share_bar_svg(share)
    fill = tag.rect(width: svg_number(84 * share.to_f.clamp(0, 1)), height: 8, rx: 4, fill: IRIS)
    tag.svg safe_join([ tag.rect(width: 84, height: 8, rx: 4, fill: GRID), fill ]), width: 84, height: 8, viewBox: "0 0 84 8",
      class: "shrink-0", "aria-hidden": true
  end

  # The overview's p95 · 24h sparkline: gaps take the last known value; nil
  # when the transaction has no hourly p95 at all.
  def apm_p95_sparkline(values, slower:)
    known = values.compact
    return if known.empty?

    last = known.first
    filled = values.map { |value| last = value || last }
    sparkline_svg filled, color: slower ? ChartHelper::CORAL : ChartHelper::IRIS, width: 120, height: 28
  end

  private
    def apm_chart_svg(shapes, label)
      tag.svg safe_join(shapes), width: "100%", height: HEIGHT, viewBox: "0 0 #{WIDTH} #{HEIGHT}", preserveAspectRatio: "none",
        class: "block", role: "img", "aria-label": label
    end

    def apm_grid_lines
      (0...Y_INTERVALS).map do |i|
        y = svg_number(HEIGHT * i.fdiv(Y_INTERVALS))
        tag.path(d: "M0 #{y}H#{WIDTH}", stroke: GRID, "stroke-width": 1, "vector-effect": "non-scaling-stroke")
      end
    end

    def apm_baseline = tag.path(d: "M0 #{HEIGHT}H#{WIDTH}", stroke: AXIS, "stroke-width": 1, "vector-effect": "non-scaling-stroke")

    def apm_y(value, max) = svg_number(HEIGHT - (value.to_f / max * HEIGHT).clamp(0, HEIGHT))

    # One bin's stacked rects (bottom-up STACK_ORDER) in a <g> with its <title>.
    def apm_bin_group(bin, index, slot, max)
      return unless bin.split

      base = 0.0
      rects = STACK_ORDER.map do |layer|
        value = bin.split[layer]
        rect = apm_stack_rect(index, slot, base, value, max, LAYER_COLORS.fetch(layer))
        base += value
        rect
      end
      tag.g safe_join([ tag.title(apm_bin_title(bin)), *rects ])
    end

    def apm_stack_rect(index, slot, base, value, max, fill)
      top, bottom = apm_y(base + value, max).to_f, apm_y(base, max).to_f
      tag.rect x: svg_number(index * slot + slot * 0.1), y: svg_number(top), width: svg_number(slot * 0.8),
        height: svg_number([ bottom - top, 0 ].max), fill:
    end

    def apm_bin_title(bin)
      "#{bin.time.in_time_zone.strftime('%b %-d, %H:%M')} · average #{apm_duration(bin.average_ms)} · p95 #{apm_duration(bin.p95)}"
    end

    # A polyline through the bin centres; a nil value breaks the line.
    def apm_line_path(values, slot, max, style)
      d = values.each_with_index.filter_map do |value, i|
        next if value.nil?

        command = i.zero? || values[i - 1].nil? ? "M" : "L"
        "#{command}#{svg_number(i * slot + slot / 2)} #{apm_y(value, max)}"
      end.join(" ")
      tag.path d: d.presence || "M0 #{HEIGHT}", fill: "none", stroke: style[:stroke], "stroke-width": style[:width],
        "stroke-dasharray": style[:dash], "stroke-linejoin": "round", "vector-effect": "non-scaling-stroke"
    end

    # Left to right: Database, External HTTP, Views, Ruby.
    def apm_split_segments(split, total, length, height)
      offset = 0.0
      PerformanceHelper::LAYER_NAMES.keys.filter_map do |layer|
        width = length * split[layer].to_f / total
        next if width <= 0

        rect = tag.rect(x: apm_percent_attr(offset), width: apm_percent_attr(width), height:, fill: LAYER_COLORS.fetch(layer))
        offset += width
        rect
      end
    end

    def apm_tick_anchor(index, count)
      return "start" if index.zero?

      index == count - 1 ? "end" : "middle"
    end

    def apm_percent_attr(fraction) = "#{svg_number(fraction * 100)}%"

    def apm_clip_id
      @apm_clip_sequence = @apm_clip_sequence.to_i + 1
      "apm-split-#{@apm_clip_sequence}"
    end
end
