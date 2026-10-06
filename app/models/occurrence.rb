# One captured event. Everything captured is kept in the encrypted, normalised
# JSON payload (docs/ARCHITECTURE.md §3.3) and exposed through the readers below.
class Occurrence < ApplicationRecord
  RETAINED_PER_ISSUE = 1_000

  belongs_to :issue, inverse_of: :occurrences
  belongs_to :project, inverse_of: :occurrences

  encrypts :payload

  scope :latest_first, -> { order(id: :desc) }

  def self.latest = latest_first.first

  def self.oldest = order(:id).first

  def to_param = uuid

  def data
    @data ||= parse_payload
  end

  def reload(...)
    @data = nil
    super
  end

  def exception_message = data.dig("exception", "message").to_s
  def frames = array_at("exception", "backtrace").grep(Hash)
  def request = hash_at("request")
  def params = hash_at("params")
  def headers = hash_at("headers")
  def session_data = hash_at("session")
  def job = hash_at("job")
  def user = hash_at("user")
  def breadcrumbs = array_at("breadcrumbs").grep(Hash)
  def context = hash_at("context")
  def tags = hash_at("tags")
  def notifier = hash_at("notifier")
  def transaction_name = data["transaction"].presence

  private
    def parse_payload
      parsed = JSON.parse(payload.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def hash_at(*path)
      value = data.dig(*path)
      value.is_a?(Hash) ? value : {}
    end

    def array_at(*path)
      value = data.dig(*path)
      value.is_a?(Array) ? value : []
    end
end
