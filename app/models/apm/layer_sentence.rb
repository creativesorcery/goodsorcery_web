# The sentence under the endpoint page's "Where time goes" bars
# (docs/ARCHITECTURE.md §13.9): which layer takes the most time around p95
# and p99, and where typical requests spend theirs.
#
#   Apm::LayerSentence.new(report.bars, noun: "requests").sentence
#   # => "Around p95 and p99, the database takes the most time (49% and 56%).
#   #     Typical requests mostly wait on external HTTP."
class Apm::LayerSentence
  NAMES = { db: "the database", http: "external HTTP", view: "rendering", app: "app code" }.freeze
  WAITING_LAYERS = %i[db http].freeze

  def initialize(bars, noun:)
    @bars = bars.index_by(&:key)
    @noun = noun
  end

  # nil unless the Average, p95 and p99 bars all have time in them.
  def sentence
    average, p95, p99 = @bars.values_at(:average, 95, 99)
    return unless [ average, p95, p99 ].all? { it&.value&.positive? }

    "#{tail_clause(p95, p99)} #{typical_clause(top_layer(average), top_layer(p95))}"
  end

  private
    def tail_clause(p95, p99)
      layer, other = top_layer(p95), top_layer(p99)
      if layer == other
        "Around p95 and p99, #{NAMES[layer]} takes the most time (#{share(p95, layer)} and #{share(p99, layer)})."
      else
        "Around p95, #{NAMES[layer]} takes the most time (#{share(p95, layer)}); around p99, #{NAMES[other]} does (#{share(p99, other)})."
      end
    end

    def typical_clause(layer, tail_layer)
      return "Typical #{@noun} spend most of their time there too." if layer == tail_layer
      return "Typical #{@noun} mostly wait on #{NAMES[layer]}." if WAITING_LAYERS.include?(layer)

      "Typical #{@noun} spend most of their time in #{NAMES[layer]}."
    end

    def top_layer(bar) = bar.split.max_by { |_, ms| ms }.first

    def share(bar, layer) = "#{(100 * bar.split[layer] / bar.value).round}%"
end
