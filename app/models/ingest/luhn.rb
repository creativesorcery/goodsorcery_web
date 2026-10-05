# Luhn checksum, used to tell real card numbers from other long digit runs.
module Ingest::Luhn
  def self.valid?(text)
    digits = text.to_s.delete("^0-9").reverse.chars.map(&:to_i)
    return false unless digits.size.between?(13, 19)

    sum = digits.each_with_index.sum { |digit, index| index.odd? ? double(digit) : digit }
    (sum % 10).zero?
  end

  def self.double(digit)
    doubled = digit * 2
    doubled > 9 ? doubled - 9 : doubled
  end
  private_class_method :double
end
