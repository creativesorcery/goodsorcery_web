# The issue page's tag distribution bars (IssueTagCount.distribution).
module IssueTagsHelper
  PALETTE = [ ChartHelper::IRIS, ChartHelper::IRIS_DEEP, ChartHelper::IRIS_SOFT, ChartHelper::LILAC, ChartHelper::MINT ].freeze
  SUSPICIOUS_SHARE = 0.8
  ENVIRONMENT_KEY = "environment".freeze

  # One value dominating a key with several values, e.g. 92% on one coupon.
  def suspicious_tag?(key)
    key.distinct_count >= 2 && key.values.first&.share.to_f >= SUSPICIOUS_SHARE
  end

  # Stacked bar segments: the top values, then the rest in paper. The
  # environment key (set from the API key, never captured) draws each
  # environment in its tone.
  def tag_segments(key)
    suspicious = suspicious_tag?(key)
    segments = key.values.each_with_index.map do |value, index|
      { share: value.share, color: tag_value_color(key, value, index, suspicious), title: "#{share_percent(value.share)} #{value.value}" }
    end
    segments << { share: tag_remainder(key), color: ChartHelper::PAPER } if tag_remainder(key).positive?
    segments
  end

  def share_percent(share)
    "#{(share.to_f * 100).round}%"
  end

  private
    def tag_value_color(key, value, index, suspicious)
      return environment_color(value.value) if key.key == ENVIRONMENT_KEY && !suspicious

      tag_color(index, suspicious)
    end

    def tag_color(index, suspicious)
      return (index.zero? ? ChartHelper::CORAL : ChartHelper::PAPER) if suspicious

      PALETTE.fetch(index, ChartHelper::IRIS_SOFT)
    end

    def tag_remainder(key)
      (1 - key.values.sum(&:share)).round(4)
    end
end
