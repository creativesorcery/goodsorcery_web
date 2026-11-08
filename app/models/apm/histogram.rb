# The fixed log-scale duration histogram shared with every client (scheme gs-v1,
# docs/ARCHITECTURE.md §13.1). Never change these bounds without a new scheme:
# both repos assert the literal list element by element.
module Apm::Histogram
  # Upper bounds in milliseconds of buckets 0..29; bucket 30 is open-ended.
  BOUNDS_MS = [
    1, 1.5, 2, 3, 4.5, 6.5, 9.5, 14, 20, 28,
    40, 60, 85, 125, 180, 260, 380, 550, 800, 1_150,
    1_700, 2_450, 3_550, 5_100, 7_500, 11_000, 16_000, 23_000, 33_000, 48_000
  ].freeze
  BUCKETS = 31
  LAST = BUCKETS - 1
  SCHEME = "gs-v1".freeze

  # The bucket of a duration: the number of bounds <= ms.
  def self.index(ms) = BOUNDS_MS.bsearch_index { it > ms } || LAST

  def self.zeros = Array.new(BUCKETS, 0)

  def self.float_zeros = Array.new(BUCKETS, 0.0)
end
