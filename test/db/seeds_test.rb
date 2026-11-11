require "test_helper"

# db/seeds.rb creates the demo owner alex@example.com / password, whose
# credentials are printed in the README, so it must never reach production.
class SeedsTest < ActiveSupport::TestCase
  test "db:prepare never seeds the production database" do
    production = ActiveRecord::Base.configurations.configs_for(env_name: "production", name: "primary")

    assert_not production.seeds?
  end

  test "the demo seeds refuse to run in production" do
    previous, Rails.env = Rails.env, "production"

    assert_no_difference -> { User.count + Account.count } do
      assert_raises(SystemExit) { capture_io { load Rails.root.join("db/seeds.rb").to_s } }
    end
  ensure
    Rails.env = previous
  end
end
