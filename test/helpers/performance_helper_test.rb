require "test_helper"

class PerformanceHelperTest < ActionView::TestCase
  include PerformanceHelper, ChipHelper, ::NumberHelper

  test "durations keep three significant digits and switch to seconds at 1,000 ms" do
    assert_equal "0.4 ms", apm_duration(0.4)
    assert_equal "412 ms", apm_duration(412.3)
    assert_equal "12.3 ms", apm_duration(12.34)
    assert_equal "1 s", apm_duration(999.7)
    assert_equal "1.24 s", apm_duration(1240)
    assert_equal "3.2 s", apm_duration(3200)
    assert_equal "12.4 s", apm_duration(12_400)
    assert_equal "—", apm_duration(nil)
    assert_equal [ "1.24", "s" ], apm_duration_parts(1240)
  end

  test "rates and percentages" do
    assert_equal "1,284", apm_rate(1284.2)
    assert_equal "4.5", apm_rate(4.46)
    assert_equal "0.2", apm_rate(0.2)
    assert_equal "<0.1", apm_rate(0.01)
    assert_equal "—", apm_rate(nil)
    assert_equal "1.9%", apm_percent(0.019)
    assert_equal "0.24%", apm_percent(0.0024)
    assert_equal "0%", apm_percent(0)
    assert_equal "—", apm_percent(nil)
    assert_equal "1.8×", apm_ratio(1.83)
  end

  test "tile values set the unit smaller and figures read as text" do
    assert_dom_equal %(412<span class="text-[0.56em] text-ink-300 ml-1">ms</span>), apm_tile_value(:duration, 412)
    assert_dom_equal %(0.24<span class="text-[0.56em] text-ink-300 ">%</span>), apm_tile_value(:percent, 0.0024)
    assert_equal "—", apm_tile_value(:rate, nil)
    assert_equal "1,310 per minute", apm_figure(:rate, 1310)
    assert_equal "164 ms", apm_figure(:duration, 164)
  end

  test "route lines for endpoints and jobs" do
    assert_equal "POST /checkout", apm_route_line(apm_transactions(:checkout_create))
    assert_equal "sidekiq · critical · waits 800 ms (p95)", apm_route_line(apm_transactions(:place_order_job), queue_wait_ms: 800)
    assert_equal "sidekiq · critical", apm_route_line(apm_transactions(:place_order_job))
    assert_equal [ "POST /checkout", "app/controllers/checkouts_controller.rb" ], apm_source_line(apm_transactions(:checkout_create))
  end

  test "status labels for requests and jobs" do
    assert_equal "200 OK", apm_status_label(apm_traces(:checkout_slow))
    assert_equal "500", apm_status_code(apm_traces(:checkout_failed))
    assert apm_failed_status?(apm_traces(:checkout_failed))
    job_trace = ApmTrace.new(status: nil, failed: true)
    assert_equal "Failed", apm_status_label(job_trace)
    assert_equal "OK", apm_status_code(ApmTrace.new(status: nil, failed: false))
  end

  test "span labels shorten SQL and name HTTP calls, views and enqueues" do
    details = apm_traces(:checkout_slow).details
    labels = details.spans.map { apm_span_label(it) }
    assert_equal 'SELECT "users" WHERE "id" = $1', labels.first
    assert_includes labels, "POST api.taxjar.com/v2/taxes"
    assert_includes labels, "checkouts/create.html.erb"
    assert_includes labels, "enqueue Orders::PlaceJob"
    assert_equal %w[SQL SQL HTTP View Job], details.spans.map { apm_span_type(it) }
  end

  test "formatted SQL puts clauses on their own lines and escapes everything" do
    html = formatted_sql('SELECT "products".* FROM "products" WHERE "products"."id" = $1 LIMIT $2')
    assert_equal %(SELECT "products".* FROM "products"\nWHERE "products"."id" = $1 LIMIT $2), Nokogiri::HTML5.fragment(html).text
    assert_dom_equal %(<span class="tok-k">SELECT</span> "products".* <span class="tok-k">FROM</span> "products"\n) +
      %(<span class="tok-k">WHERE</span> "products"."id" = <span class="tok-n">$1</span> <span class="tok-k">LIMIT</span> <span class="tok-n">$2</span>), html

    escaped = formatted_sql(%(SELECT "<script>alert(1)</script>" FROM x))
    assert_not_includes escaped, "<script>"
    assert_includes escaped, "&lt;script&gt;"
  end

  test "bin phrases follow the range" do
    assert_equal "every 15 minutes", apm_bin_phrase(Apm::Range.new("1d"))
    assert_equal "every minute", apm_bin_phrase(Apm::Range.new("1h"))
    assert_equal "every 2 hours", apm_bin_phrase(Apm::Range.new("7d"))
    assert_equal "every 8 hours", apm_bin_phrase(Apm::Range.new("30d"))
  end

  test "the request facts of a trace" do
    page = Apm::TracePage.new(apm_traces(:checkout_slow), cutoff: 30.days.ago)
    facts = apm_trace_facts(page).to_h
    assert_equal "200 OK", facts["Status"]
    assert_equal "web-2 · Puma worker 3", facts["Host"]
    assert_equal "Ruby 3.4.1 · Rails 8.0.2", facts["Runtime"]
    assert_equal "14 ms · 3 runs", facts["GC"]
    assert_equal "1.4M objects", facts["Allocations"]
  end
end
