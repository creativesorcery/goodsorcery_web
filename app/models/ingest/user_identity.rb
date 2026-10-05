# The affected end user, known to the database only through HMAC digests of
# their id, email and username (ARCHITECTURE.md §1.6).
class Ingest::UserIdentity
  FIELDS = { "id" => "user.id", "email" => "user.email", "username" => "user.username" }.freeze

  def initialize(user)
    @user = user.is_a?(Hash) ? user : {}
  end

  def present? = digests.any?

  # Digest of the first present of id, email, username.
  def primary_digest = digests.first

  def digests
    @digests ||= FIELDS.filter_map do |field, namespace|
      value = IssueUser.normalize(namespace, @user[field])
      PrivateDigest.hexdigest(namespace, value) if value.present?
    end
  end
end
