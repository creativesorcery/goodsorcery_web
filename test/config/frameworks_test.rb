require "test_helper"

# The app has no attachments, inbound mail or rich text. Loading those
# frameworks would mount unauthenticated /rails/active_storage/* and
# /rails/action_mailbox/* endpoints outside the Authentication concern.
class FrameworksTest < ActionDispatch::IntegrationTest
  test "Active Storage, Action Mailbox and Action Text are not loaded" do
    assert_not defined?(ActiveStorage::Engine)
    assert_not defined?(ActionMailbox::Engine)
    assert_not defined?(ActionText::Engine)
  end

  test "no framework endpoints are mounted under /rails" do
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

    assert_empty paths.grep(%r{\A/rails/})
  end

  test "the direct upload endpoint is not routed" do
    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "x.txt", byte_size: 1, checksum: "x" } }

    assert_response :not_found
  end
end
