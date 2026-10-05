# Per-issue tag value counts. Keys are plaintext; values are encrypted and
# identified by an HMAC so they can be upserted without decrypting.
class IssueTagCount < ApplicationRecord
  module TagDistribution
    # `capped`: the key reached VALUES_PER_KEY and counts later values as "Other values".
    Key = Data.define(:key, :distinct_count, :total, :values, :capped) do
      def capped? = capped
    end
    Value = Data.define(:value, :count, :share)
  end

  KEY_FORMAT = /\A[a-z0-9_.\-]{1,32}\z/i
  # Ingest bounds (Ingest::TagRows): distinct values per key, keys per issue.
  VALUES_PER_KEY = 100
  KEYS_PER_ISSUE = 40
  OTHER_DIGEST = "other".freeze
  OTHER_VALUE = "Other values".freeze

  belongs_to :issue, inverse_of: :tag_counts

  encrypts :value

  def self.value_digest(key, value) = PrivateDigest.hexdigest("tag.#{key}", value)

  # Top `per_key` values per tag key with shares, from one window-function
  # query over at most KEYS_PER_ISSUE * (VALUES_PER_KEY + 1) rows.
  def self.distribution(issue, per_key: 5)
    ranked_rows(issue, per_key).group_by(&:key).map do |key, rows|
      total = rows.first.total.to_i
      values = rows.map { |row| TagDistribution::Value.new(row.value, row.count, row.count.fdiv([ total, 1 ].max)) }
      TagDistribution::Key.new(key, rows.first.distinct_count.to_i, total, values, rows.first.capped)
    end
  end

  def self.ranked_rows(issue, per_key)
    ranked = where(issue:).select(
      "issue_tag_counts.*",
      "ROW_NUMBER() OVER (PARTITION BY key ORDER BY count DESC, value_digest) AS rank",
      "COUNT(*) FILTER (WHERE value_digest <> '#{OTHER_DIGEST}') OVER (PARTITION BY key) AS distinct_count",
      "BOOL_OR(value_digest = '#{OTHER_DIGEST}') OVER (PARTITION BY key) AS capped",
      "SUM(count) OVER (PARTITION BY key) AS total"
    )
    from(ranked, :issue_tag_counts).where("rank <= ?", per_key).order(:key, :rank).to_a
  end
  private_class_method :ranked_rows
end
