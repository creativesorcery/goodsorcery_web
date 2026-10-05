module NumberHelper
  COMPACT_UNITS = [ [ 1_000_000_000, "B" ], [ 1_000_000, "M" ], [ 1_000, "k" ] ].freeze

  # 1284 → "1,284"
  def delimited(number)
    number_with_delimiter(number.to_i)
  end

  # 950 → "950", 1_240 → "1.2k", 412_000 → "412k", 1_200_000 → "1.2M"
  def compact_count(number)
    number = number.to_i
    divisor, suffix = COMPACT_UNITS.find { |threshold, _| number.abs >= threshold }
    return number.to_s unless divisor

    "#{compact_quotient(number.fdiv(divisor))}#{suffix}"
  end

  private
    def compact_quotient(value)
      value = value.abs < 10 ? value.floor(1) : value.floor
      value == value.to_i ? value.to_i.to_s : value.to_s
    end
end
