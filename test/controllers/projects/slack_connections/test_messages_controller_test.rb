require "test_helper"

class Projects::SlackConnections::TestMessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @project = projects(:storefront)
    sign_in_as users(:jo) # any member, like the rest of Settings › Alerts
  end

  test "enqueues one test message with the connection id only" do
    assert_enqueued_with(job: SlackTestMessageJob, args: [ slack_connections(:storefront).id ]) do
      post project_slack_connection_test_message_path(@project)
    end

    assert_redirected_to project_alerts_path(@project, anchor: "slack")
    assert_match(/Sending a test message/, flash[:notice])
  end

  test "one test message per 30 seconds per connection, whoever asks" do
    freeze_time
    post project_slack_connection_test_message_path(@project)
    sign_in_as users(:philip)

    assert_no_enqueued_jobs(only: SlackTestMessageJob) { post project_slack_connection_test_message_path(@project) }
    assert_equal "A test message was sent less than 30 seconds ago.", flash[:alert]

    travel 30.seconds
    assert_enqueued_jobs(1, only: SlackTestMessageJob) { post project_slack_connection_test_message_path(@project) }
  end

  test "rate limited per user" do
    with_memory_cache do
      5.times { post project_slack_connection_test_message_path(@project) }
      assert_equal "A test message was sent less than 30 seconds ago.", flash[:alert]

      slack_connections(:storefront).update_columns(test_sent_at: nil) # the per-connection gap is open again
      assert_no_enqueued_jobs(only: SlackTestMessageJob) { post project_slack_connection_test_message_path(@project) }
      assert_equal "Too many test messages. Try again in a minute.", flash[:alert]
    end
  end

  test "an app without Slack is a 404" do
    post project_slack_connection_test_message_path(projects(:marketing))

    assert_response :not_found
  end

  test "outsiders get 404" do
    sign_in_as users(:outsider)

    assert_no_enqueued_jobs { post project_slack_connection_test_message_path(@project) }
    assert_response :not_found
  end

  test "requires sign in" do
    sign_out

    post project_slack_connection_test_message_path(@project)
    assert_redirected_to new_session_path
  end
end
