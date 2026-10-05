class Membership < ApplicationRecord
  belongs_to :account, inverse_of: :memberships
  belongs_to :user, inverse_of: :memberships

  enum :role, { owner: "owner", member: "member" }, validate: true

  validates :user_id, uniqueness: { scope: :account_id }

  # Losing access must also end any browser session working in that account.
  after_destroy_commit :end_sessions

  private
    def end_sessions
      Session.where(user_id:, account_id:).delete_all
    end
end
