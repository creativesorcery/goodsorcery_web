require "test_helper"
require_relative "apm_test_support"

class Apm::BatchProcessorTest < ActiveSupport::TestCase
  include ApmFixtureClock

  include ApmTestSupport

  setup do
    @project = projects(:storefront)
    @minute = current_minute - 1.minute
    @checkout = apm_transactions(:checkout_create)
  end

  def minute_row(transaction, minute = @minute) = ApmMinuteStat.find_by(apm_transaction_id: transaction.id, minute:)

  def hour_row(transaction, minute = @minute) = ApmHourlyStat.find_by(apm_transaction_id: transaction.id, hour: TimeSeries.align(minute, 1.hour))

  test "metrics add element-wise to the minute, hourly and total rows" do
    minute_before = minute_row(@checkout).attributes
    hour_before = hour_row(@checkout).attributes
    total_before = minute_row(apm_transactions(:storefront_web_total)).requests_count

    assert_equal 1, process_batch(metrics_body)

    after = minute_row(@checkout)
    assert_equal minute_before["requests_count"] + 3, after.requests_count
    assert_equal minute_before["bucket_counts"][15] + 2, after.bucket_counts[15]
    assert_equal minute_before["bucket_counts"][20] + 1, after.bucket_counts[20]
    assert_in_delta minute_before["bucket_db_ms"][20] + 600.0, after.bucket_db_ms[20]
    assert_in_delta minute_before["duration_ms_sum"] + 1400.0, after.duration_ms_sum
    assert_equal hour_before["requests_count"] + 3, hour_row(@checkout).requests_count
    assert_equal total_before + 3, minute_row(apm_transactions(:storefront_web_total)).requests_count
  end

  test "new transactions, minutes and the total rows are created on demand" do
    project = projects(:marketing)
    body = metrics_body([ metrics_transaction(name: "PagesController#home"),
                          metrics_transaction(name: "Mailers::DigestJob", kind: "job", queue_wait: [ [ 11, 2 ] ], queue_wait_ms: 90.0) ])
    process_batch(body, key: api_keys(:marketing_production))

    names = project.apm_transactions.order(:name).pluck(:name, :kind, :total)
    assert_equal [ [ "All background jobs", "job", true ], [ "All web requests", "web", true ],
                   [ "Mailers::DigestJob", "job", false ], [ "PagesController#home", "web", false ] ], names
    job = project.apm_transactions.find_by!(name: "Mailers::DigestJob")
    assert_equal [ "sidekiq", "critical" ], [ job.adapter, job.queue ]
    assert_equal 2, minute_row(job).queue_wait_counts[11]
    assert_in_delta 90.0, minute_row(job).queue_wait_ms_sum
    assert_equal "POST /checkout", project.apm_transactions.find_by!(name: "PagesController#home").route_label
    assert_equal 3, hour_row(ApmTransaction.total_for(project, "production", "job")).requests_count
  end

  test "duplicate keys merge in Ruby and rows are upserted in id order" do
    body = metrics_body(minutes: [ { minute: @minute.iso8601, transactions: [ metrics_transaction, metrics_transaction(count: 5) ] },
                                   { minute: (@minute - 1.minute).iso8601, transactions: [ metrics_transaction(name: "ProductsController#show") ] } ])
    before = minute_row(@checkout).requests_count
    statements = statements_in { process_batch(body) }

    assert_equal before + 8, minute_row(@checkout).requests_count
    insert = statements.find { it.start_with?('INSERT INTO "apm_minute_stats"') }
    ids = insert.scan(/\((\d+), '\d{4}-\d\d-\d\d \d\d:\d\d:\d\d'/).flatten.map(&:to_i)
    assert_equal ids.sort, ids
  end

  test "minutes outside the window are skipped" do
    old, future = current_minute - 25.hours, current_minute + 3.minutes
    body = metrics_body(minutes: [ old, future ].map { { minute: it.iso8601, transactions: [ metrics_transaction ] } })
    assert_equal 0, process_batch(body)
    assert_nil minute_row(@checkout, old)
    assert_nil minute_row(@checkout, future)
  end

  test "a batch is processed once, its body cleared" do
    id = store_batch(metrics_body)
    assert_equal 1, Apm::BatchProcessor.new(id).process
    assert_nil Apm::BatchProcessor.new(id).process
    batch = ApmInboundBatch.find(id)
    assert batch.processed?
    assert_nil batch.body
    assert_nil Apm::BatchProcessor.new(-1).process
  end

  test "names past the cap fold into (other), which is created on demand outside the cap" do
    now = Time.current
    filler = (Apm::MAX_TRANSACTIONS - 2).times.map do |index|
      { project_id: @project.id, environment: "production", kind: "web", name: "Filler#{index}Controller#index",
        first_seen_at: now, last_seen_at: now }
    end
    ApmTransaction.insert_all(filler)

    process_batch(metrics_body([ metrics_transaction(name: "BrandNewController#a"), metrics_transaction(name: "BrandNewController#b") ]))

    scope = @project.apm_transactions.for_environment("production").web
    assert_not scope.exists?(name: "BrandNewController#a")
    other = scope.find_by!(name: ApmTransaction::OTHER_NAME)
    assert_equal 6, minute_row(other).requests_count
    assert_equal Apm::MAX_TRANSACTIONS, scope.listed.where.not(name: ApmTransaction::OTHER_NAME).count
  end

  test "the last new names fill the cap exactly" do
    now = Time.current
    ApmTransaction.insert_all((Apm::MAX_TRANSACTIONS - 3).times.map do |index|
      { project_id: @project.id, environment: "production", kind: "web", name: "Filler#{index}", first_seen_at: now, last_seen_at: now }
    end)
    process_batch(metrics_body([ metrics_transaction(name: "New#a"), metrics_transaction(name: "New#b") ]))
    scope = @project.apm_transactions.for_environment("production").web
    assert scope.exists?(name: "New#a")
    assert_not scope.exists?(name: "New#b")
    assert_equal 3, minute_row(scope.find_by!(name: ApmTransaction::OTHER_NAME)).requests_count
  end

  test "a client name equal to a total row's name is counted under (other)" do
    process_batch(metrics_body([ metrics_transaction(name: "All web requests") ]))
    other = @project.apm_transactions.find_by!(environment: "production", kind: "web", name: ApmTransaction::OTHER_NAME)
    assert_equal 3, minute_row(other).requests_count
  end

  test "null bytes are dropped from names and labels instead of failing the batch" do
    process_batch(metrics_body([ metrics_transaction(name: "Orders#\u0000show", route: "/orders/\u0000:id") ]))
    transaction = @project.apm_transactions.find_by!(environment: "production", kind: "web", name: "Orders#show")
    assert_equal "/orders/:id", transaction.route
    assert_equal 3, minute_row(transaction).requests_count
  end

  test "labels and last_seen_at are refreshed at most hourly" do
    @checkout.update_columns(last_seen_at: 2.hours.ago, route: "/old")
    process_batch(metrics_body)
    assert_equal "/checkout", @checkout.reload.route
    assert_in_delta Time.current, @checkout.last_seen_at, 5

    @checkout.update_columns(route: "/kept")
    process_batch(metrics_body)
    assert_equal "/kept", @checkout.reload.route
  end

  test "metrics cost at most 8 statements" do
    id = store_batch(metrics_body([ metrics_transaction, metrics_transaction(name: "FreshController#a"), metrics_transaction(name: "Fresh::Job", kind: "job") ]))
    apm_transactions(:storefront_jobs_total).update_columns(last_seen_at: 2.hours.ago)
    statements = statements_in { Apm::BatchProcessor.new(id).process }
    assert_operator statements.size, :<=, 8, statements.join("\n")
  end

  test "a slower trace replaces the stored one; a faster or equal one doesn't" do
    process_batch(traces_body([ trace_hash(duration_ms: 1000.0) ]), kind: "traces")
    stored = ApmTrace.find_by!(apm_transaction: @checkout, minute: @minute)
    assert_in_delta 1000.0, stored.duration_ms

    process_batch(traces_body([ trace_hash(duration_ms: 900.0), trace_hash(duration_ms: 1000.0) ]), kind: "traces")
    assert_equal stored.uuid, ApmTrace.find_by!(apm_transaction: @checkout, minute: @minute).uuid

    slower = trace_hash(duration_ms: 2000.0, status: 500)
    process_batch(traces_body([ slower ]), kind: "traces")
    replaced = ApmTrace.find_by!(apm_transaction: @checkout, minute: @minute)
    assert_equal slower[:id], replaced.uuid
    assert_equal [ 2000.0, 500, true ], [ replaced.duration_ms, replaced.status, replaced.failed ]
  end

  test "a batch keeps the slowest trace per transaction and minute" do
    fast, slow = trace_hash(duration_ms: 10.0), trace_hash(duration_ms: 20.0)
    process_batch(traces_body([ fast, slow ]), kind: "traces")
    assert_equal slow[:id], ApmTrace.find_by!(apm_transaction: @checkout, minute: @minute).uuid
  end

  test "a resent trace id for another minute gets a fresh id instead of failing" do
    trace = trace_hash(duration_ms: 10.0)
    process_batch(traces_body([ trace ]), kind: "traces")
    process_batch(traces_body([ trace.merge(minute: (@minute - 1.minute).iso8601) ]), kind: "traces")
    assert_equal 2, ApmTrace.where(apm_transaction: @checkout, minute: [ @minute, @minute - 1.minute ]).count
  end

  test "traces older than 2 hours are skipped" do
    assert_equal 0, process_batch(traces_body([ trace_hash(minute: current_minute - 3.hours) ]), kind: "traces")
  end

  test "traces cost at most 7 statements" do
    id = store_batch(traces_body([ trace_hash, trace_hash(name: "FreshController#b") ]), kind: "traces")
    @checkout.update_columns(last_seen_at: 2.hours.ago)
    statements = statements_in { Apm::BatchProcessor.new(id).process }
    assert_operator statements.size, :<=, 7, statements.join("\n")
  end
end
