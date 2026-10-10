class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_verified_at, :datetime

    # Users who signed up before verification existed keep full access.
    up_only { execute "UPDATE users SET email_verified_at = created_at" }
  end
end
