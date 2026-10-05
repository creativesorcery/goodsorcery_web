# An affected end user of an issue, known only by HMAC digests of their
# id / email / username. Plaintext identities are never stored here.
class IssueUser < ApplicationRecord
  NAMESPACES = %w[user.id user.email user.username].freeze

  belongs_to :issue, inverse_of: :issue_users
  belongs_to :project

  class << self
    def count_for(issue, digest)
      where(issue:, user_digest: digest).pick(:events_count) || 0
    end

    def distinct_users(project, since:)
      where(project:, last_seen_at: since..).distinct.count(:user_digest)
    end

    # Digests of a free-text identity under every user namespace, for search.
    def identity_digests_for(value)
      return [ value.to_s.downcase ] if PrivateDigest.digest?(value)

      NAMESPACES.map { |namespace| PrivateDigest.hexdigest(namespace, normalize(namespace, value)) }
    end

    def normalize(namespace, value)
      namespace == "user.email" ? value.to_s.strip.downcase : value.to_s.strip
    end
  end
end
