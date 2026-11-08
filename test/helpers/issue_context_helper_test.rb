require "test_helper"

class IssueContextHelperTest < ActionView::TestCase
  test "flatten_context joins nested keys and keeps empty hashes as values" do
    flat = flatten_context({ "runtime" => { "ruby" => "3.4.1", "rails" => { "version" => "8.1" } }, "env" => {}, "host" => "web-1" })

    assert_equal({ "runtime.ruby" => "3.4.1", "runtime.rails.version" => "8.1", "env" => {}, "host" => "web-1" }, flat)
  end

  test "flatten_context shows a runtime list as one key per runtime" do
    flat = flatten_context({ "runtime" => [ { "name" => "Rust", "version" => "1.82.0" }, { "name" => "axum", "version" => "0.8.1" } ],
                             "process" => "worker 3" })

    assert_equal({ "runtime.Rust" => "1.82.0", "runtime.axum" => "0.8.1", "process" => "worker 3" }, flat)
    assert_equal({ "runtime" => [ "a", "b" ] }, flatten_context({ "runtime" => [ "a", "b" ] }))
  end

  test "affected user name falls back from name to username to the email's local part" do
    assert_equal "Mara", affected_user_name({ "name" => "Mara", "username" => "mk" })
    assert_equal "mk", affected_user_name({ "username" => "mk", "email" => "m@x.io" })
    assert_equal "m", affected_user_name({ "email" => "m@x.io" })
    assert_equal "Anonymous user", affected_user_name({})
  end

  test "affected user identity never shows the email domain" do
    assert_equal "id 5521 · mara@…", affected_user_identity({ "id" => 5521, "email" => "mara@example.com" })
  end

  test "job rows follow the field order, label the framework and skip blanks" do
    occurrence = Occurrence.new(payload: { job: { queue: "mailers", class: "ActionMailer::MailDeliveryJob", framework: "active_job",
                                                  mailer: "UserMailer", action: "welcome", priority: "" } }.to_json)

    assert_equal [ [ "Framework", "Active Job", nil ], [ "Job class", "ActionMailer::MailDeliveryJob", "text-lilac-300" ],
                   [ "Mailer", "UserMailer", nil ], [ "Mailer action", "welcome", nil ], [ "Queue", "mailers", nil ] ],
                 job_rows(occurrence)
  end

  test "job arguments are an array or object, otherwise empty" do
    assert_equal [ 1 ], job_arguments(Occurrence.new(payload: { job: { arguments: [ 1 ] } }.to_json))
    assert_equal({ "a" => 1 }, job_arguments(Occurrence.new(payload: { job: { arguments: { a: 1 } } }.to_json)))
    assert_equal [], job_arguments(Occurrence.new(payload: { job: { arguments: "x" } }.to_json))
  end

  test "the Job tab opens first only for a job without a request" do
    job = { job: { class: "PlaceJob" } }
    assert_equal "job", initial_context_tab(Occurrence.new(payload: job.to_json))
    assert_equal "request", initial_context_tab(Occurrence.new(payload: job.merge(request: { url: "/x" }).to_json))
    assert_equal "request", initial_context_tab(Occurrence.new(payload: {}.to_json))
  end

  test "request rows are empty without a request section, even with a transaction" do
    assert_equal [], request_rows(Occurrence.new(payload: { transaction: "PlaceJob", request: {} }.to_json))
  end
end
