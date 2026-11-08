# Demo data for local development: the "Acme Labs" account from the approved
# mockups with five projects, issues, occurrences, rollups, tags, affected users
# and activity, uptime monitors and a week of performance data for storefront.
# Everything is created through the models, so captured data is encrypted and
# identities are stored only as HMAC digests.
#
#   bin/rails db:seed      (skips itself when the demo user already exists)

class DemoSeeds
  EMAIL = "philip@example.com".freeze
  PASSWORD = "password".freeze

  END_USERS = [
    { id: "5521", email: "mara@example.com", username: "mara", name: "Mara Lindqvist" },
    { id: "6012", email: "sam@example.com", username: "samk", name: "Sam Kowalski" },
    { id: "7130", email: "ines@example.com", username: "ines", name: "Inès Duval" },
    { id: "8044", email: "tomasz@example.com", username: "tomasz", name: "Tomasz Nowak" }
  ].freeze

  PROJECTS = [
    { name: "storefront", platform: "rails", runtime_label: "Rails 8.0 · Ruby 3.4", issue_prefix: "GS",
      issues_sequence: 1041, environments: %w[production staging], first_event_at: 280.days.ago, color: "coral" },
    { name: "billing-api", platform: "rails", runtime_label: "Rails 7.2 API · Ruby 3.3", issue_prefix: "BA",
      issues_sequence: 0, environments: %w[production], first_event_at: 200.days.ago, color: "iris" },
    { name: "backoffice", platform: "rails", runtime_label: "Rails 8.0 · Hotwire", issue_prefix: "BO",
      issues_sequence: 0, environments: %w[production], first_event_at: 90.days.ago, color: "mint" },
    { name: "fulfillment-workers", platform: "rails", runtime_label: "Sidekiq · Rails 8.0", issue_prefix: "FW",
      issues_sequence: 0, environments: %w[production], first_event_at: 150.days.ago, color: "lilac" },
    { name: "marketing-site", platform: "rails", runtime_label: nil, issue_prefix: "MS",
      issues_sequence: 0, environments: %w[production staging], first_event_at: nil, color: "iris" }
  ].freeze

  # [class, redacted message, file, line, method, transaction, first seen, last seen, events, users, kind, assignee]
  ISSUES = {
    "storefront" => [
      [ "NoMethodError", "undefined method `price_cents' for nil", "app/services/cart_total.rb", 42, "line_total", "CheckoutsController#create", 3.hours, 2.minutes, 1284, 212, :new, :philip ],
      [ "ActiveRecord::RecordNotUnique", "PG::UniqueViolation: duplicate key value violates unique constraint \"index_orders_on_idempotency_key\"", "app/jobs/orders/place_job.rb", 27, "perform", "Orders::PlaceJob", 41.days, 6.minutes, 60, 41, :regressed, nil ],
      [ "Stripe::CardError", "Your card was declined.", "app/controllers/payments_controller.rb", 31, "confirm", "PaymentsController#confirm", 270.days, 11.minutes, 4102, 38, :steady, :jo ],
      [ "Net::ReadTimeout", "Net::ReadTimeout with #<TCPSocket:(closed)>", "lib/shipping/ups_client.rb", 88, "fetch_rates", "Shipping::RatesFetcher", 12.days, 24.minutes, 73, 51, :steady, nil ],
      [ "ActionView::Template::Error", "undefined local variable or method `variant' for #<ActionView::Base>", "app/views/products/_gallery.html.erb", 14, "_app_views_products__gallery", "ProductsController#show", 52.minutes, 38.minutes, 10, 9, :new, nil ],
      [ "Redis::CannotConnectError", "Error connecting to Redis on cache.internal:[n] (Errno::ECONNREFUSED)", "config/initializers/cache.rb", 9, "block in <main>", "Rails.cache", 13.hours, 11.hours, 2880, 104, :steady, nil ],
      [ "ActionController::InvalidAuthenticityToken", "Can't verify CSRF token authenticity.", "app/controllers/sessions_controller.rb", 12, "create", "SessionsController#create", 1.year, 1.hour, 77, 60, :ignored, nil ],
      [ "Net::OpenTimeout", "execution expired", "lib/shipping/ups_client.rb", 61, "connect", "Shipping::RatesFetcher", 30.days, 2.days, 140, 90, :resolved, nil ]
    ],
    "billing-api" => [
      [ "Faraday::TimeoutError", "timed out after [n] seconds", "app/clients/ledger_client.rb", 19, "post_invoice", "InvoicesController#create", 5.days, 20.minutes, 180, 0, :steady, nil ],
      [ "ActiveRecord::StaleObjectError", "Attempted to update a stale object: Invoice.", "app/models/invoice.rb", 77, "finalize!", "InvoicesController#update", 40.days, 3.hours, 64, 12, :steady, :jo ],
      [ "JSON::ParserError", "unexpected token at '<html>'", "app/clients/tax_client.rb", 33, "parse", "TaxQuotesController#show", 9.days, 5.hours, 22, 4, :steady, nil ]
    ],
    "backoffice" => [
      [ "Pundit::NotAuthorizedError", "not allowed to update? this Refund", "app/controllers/refunds_controller.rb", 22, "update", "RefundsController#update", 40.days, 12.days, 31, 6, :resolved, nil ]
    ],
    "fulfillment-workers" => [
      [ "Faraday::ConnectionFailed", "Failed to open TCP connection to api.shipbob.com:[n]", "app/jobs/shipments/sync_job.rb", 18, "perform", "Shipments::SyncJob", 30.minutes, 31.minutes, 12, 0, :new, nil ],
      [ "Sidekiq::Shutdown", "Sidekiq::Shutdown", "app/jobs/labels/print_job.rb", 40, "perform", "Labels::PrintJob", 60.days, 2.hours, 420, 0, :steady, nil ],
      [ "Aws::S3::Errors::SlowDown", "Please reduce your request rate.", "app/jobs/manifests/upload_job.rb", 25, "perform", "Manifests::UploadJob", 20.days, 4.hours, 95, 0, :steady, :philip ]
    ]
  }.freeze

  def run
    return puts("Demo data already present. Sign in as #{EMAIL} / #{PASSWORD}") if User.exists?(email_address: EMAIL)

    ActiveRecord::Base.transaction do
      create_people
      PROJECTS.each { |spec| seed_project(spec) }
      DemoUptime.new(@account).seed
      DemoApm.new(@account.projects.find_by!(name: "storefront")).seed
    end
    puts "Seeded Acme Labs. Sign in as #{EMAIL} / #{PASSWORD} (also jo@example.com / #{PASSWORD})"
  end

  private
    def create_people
      # Hosted, a stored quota above the demo traffic; self-hosted ignores it.
      @account = Account.create!(name: "Acme Labs", entitlement_values: { "monthly_event_quota" => 1_000_000 })
      @users = {
        philip: User.create!(name: "Philip Nguyen", email_address: EMAIL, password: PASSWORD, email_verified_at: Time.current),
        jo: User.create!(name: "Jo Martin", email_address: "jo@example.com", password: PASSWORD, email_verified_at: Time.current)
      }
      @account.memberships.create!(user: @users[:philip], role: :owner)
      @account.memberships.create!(user: @users[:jo], role: :member)
    end

    def seed_project(spec)
      project = beyond_app_limit { @account.projects.create!(spec.slice(:name, :platform, :runtime_label, :issue_prefix, :issues_sequence, :color, :first_event_at)) }
      project.api_keys.update_all(created_by_id: @users[:philip].id)
      (spec[:environments] - project.environments).each { |env| project.api_keys.create!(environment: env, created_by: @users[:philip]) }
      ISSUES.fetch(spec[:name], []).each { |row| DemoIssue.new(project, row, @users).seed }
      DemoProjectRollup.new(project).seed
    end

    # Seeded with GOODSORCERY_HOSTED=1, the demo account has more apps than
    # max_projects allows, like an account that was over its limit before
    # (docs/ARCHITECTURE.md §12.2.1): it keeps them all but can't add more.
    def beyond_app_limit
      hosted = Rails.configuration.x.hosted
      Rails.configuration.x.hosted = false
      yield
    ensure
      Rails.configuration.x.hosted = hosted
    end
end

# One mockup issue with its occurrences, rollups, tags, users and activity.
class DemoIssue
  FIELDS = %i[exception_class message file line method_name transaction_name first_ago last_ago events users kind assignee].freeze
  BROWSERS = { "Mobile Safari" => 0.62, "Chrome" => 0.28, "Firefox" => 0.1 }.freeze

  def initialize(project, row, users)
    @project = project
    @spec = FIELDS.zip(row).to_h
    @users = users
    @random = Random.new(@spec[:events])
  end

  def seed
    @issue = create_issue
    2.downto(0) { |i| create_occurrence(i) }
    IssueHourlyCount.insert_all(hourly_rows)
    IssueTagCount.insert_all(tag_rows)
    IssueUser.insert_all(user_rows) if @spec[:users].positive?
    record_activity
  end

  private
    def create_issue
      @project.issues.create!(
        number: @project.allocate_issue_number, fingerprint: Digest::SHA256.hexdigest("demo:#{@project.slug}:#{@spec[:exception_class]}"),
        exception_class: @spec[:exception_class], message: @spec[:message], transaction_name: @spec[:transaction_name],
        culprit: "#{@spec[:file]}:#{@spec[:line]} in #{@spec[:method_name]}", level: level, status: status,
        environments: @project.environments.first(1), first_seen_at: @spec[:first_ago].ago, last_seen_at: @spec[:last_ago].ago,
        regressed_at: (@spec[:last_ago].ago if @spec[:kind] == :regressed), resolved_at: (@spec[:last_ago].ago + 1.hour if @spec[:kind] == :resolved),
        events_count: @spec[:events], users_count: @spec[:users], assignee: @users[@spec[:assignee]]
      )
    end

    def status
      { resolved: "resolved", ignored: "ignored" }.fetch(@spec[:kind], "unresolved")
    end

    def level
      @spec[:exception_class].include?("CardError") ? "warning" : "error"
    end

    def create_occurrence(index)
      at = @spec[:last_ago].ago - (index * (@spec[:first_ago] - @spec[:last_ago]) / 3)
      person = DemoSeeds::END_USERS[index % DemoSeeds::END_USERS.size] if @spec[:users].positive?
      @issue.occurrences.create!(
        project: @project, uuid: SecureRandom.uuid_v7, occurred_at: at, received_at: at, environment: @issue.environments.first,
        release: "a1b2c3d", level: @issue.level, user_digest: person && PrivateDigest.hexdigest("user.id", person[:id]),
        payload: DemoPayload.new(@spec, person, index).to_json, created_at: at
      )
    end

    def hourly_rows
      DemoCurve.new(@spec, @random).hours.map { |hour, count| { issue_id: @issue.id, hour:, count: } }
    end

    def tag_rows
      BROWSERS.map do |browser, share|
        { issue_id: @issue.id, key: "browser", value: browser, value_digest: IssueTagCount.value_digest("browser", browser),
          count: (@spec[:events] * share).ceil }
      end
    end

    def user_rows
      DemoSeeds::END_USERS.first([ @spec[:users], 4 ].min).map.with_index do |person, i|
        { issue_id: @issue.id, project_id: @project.id, user_digest: PrivateDigest.hexdigest("user.id", person[:id]),
          identity_digests: identity_digests(person), events_count: 1 + i * 2,
          first_seen_at: @issue.first_seen_at, last_seen_at: @issue.last_seen_at }
      end
    end

    def identity_digests(person)
      [ PrivateDigest.hexdigest("user.id", person[:id]), PrivateDigest.hexdigest("user.email", person[:email]),
        PrivateDigest.hexdigest("user.username", person[:username]) ]
    end

    def record_activity
      @issue.activities.create!(kind: :assigned, user: @issue.assignee, subject_user: @issue.assignee) if @issue.assignee
      @issue.activities.create!(kind: :resolved, user: @users[:jo]) if @issue.resolved?
      @issue.activities.create!(kind: :regressed) if @spec[:kind] == :regressed
      @issue.activities.create!(kind: :note, user: @users[:philip], body: "Looking into this one.") if @spec[:kind] == :new
    end
end

# Hourly counts: a ramp for new issues, a flat-ish line for steady ones, and a
# daily backfill over 30 days for older issues.
class DemoCurve
  def initialize(spec, random)
    @spec = spec
    @random = random
    @now = Time.current.utc.beginning_of_hour
  end

  def hours
    recent = (0...24).filter_map { |i| hour_row(@now - i.hours) }
    recent + daily_backfill
  end

  private
    def hour_row(hour)
      return if hour < @spec[:first_ago].ago.beginning_of_hour || hour > @spec[:last_ago].ago

      [ hour, base_count + @random.rand(0..3) ]
    end

    def base_count
      [ @spec[:events] / 400, 1 ].max
    end

    def daily_backfill
      (2..29).filter_map do |day|
        hour = @now.beginning_of_day - day.days + 12.hours
        [ hour, base_count * 6 ] if hour >= @spec[:first_ago].ago && hour <= @spec[:last_ago].ago
      end
    end
end

# A captured, already-scrubbed payload in the stored shape (docs/ARCHITECTURE.md §3.3).
class DemoPayload
  def initialize(spec, person, index)
    @spec = spec
    @person = person
    @index = index
  end

  def to_json(*)
    { exception: exception, transaction: @spec[:transaction_name], **layer, user: @person || {},
      breadcrumbs: breadcrumbs, context: context, tags: { browser: "Mobile Safari", environment: "production" },
      notifier: { name: "goodsorcery-ruby", version: "0.1.0" } }.to_json
  end

  private
    # Errors in app/jobs carry a job section; the rest come from a request.
    def layer
      @spec[:file].start_with?("app/jobs/") ? { job: job } : web_request
    end

    def web_request
      { request: request, params: { id: 4410 + @index, coupon: "FALL25", card_token: "[FILTERED]" },
        headers: { "Accept" => "text/html", "User-Agent" => "Mozilla/5.0 (iPhone) Mobile Safari", "Cookie" => "[FILTERED]" },
        session: { user_id: @person&.dig(:id), session_id: "[FILTERED]" } }
    end

    def job
      { framework: "active_job", class: @spec[:transaction_name], id: SecureRandom.uuid, provider_job_id: SecureRandom.hex(12),
        queue: "default", priority: "0", executions: (1 + (@index % 3)).to_s, enqueued_at: (Time.current - 45.seconds).utc.iso8601(3),
        arguments: [ "gid://shop/Order/#{4410 + @index}", { source: "checkout", api_token: "[FILTERED]" } ] }
    end

    def exception
      { class: @spec[:exception_class], message: @spec[:message].gsub("[n]", (88_100 + @index).to_s), backtrace: frames }
    end

    def frames
      [ { file: @spec[:file], line: @spec[:line], method: @spec[:method_name], in_app: true, gem: nil,
          context: { start_line: @spec[:line] - 2, lines: [ "def #{@spec[:method_name]}", "  # ...", "  raise_the_error", "end" ] },
          locals: { record_id: (4410 + @index).to_s, api_token: "[FILTERED]" } },
        { file: "gems/activerecord-8.0.1/lib/active_record/relation.rb", line: 338, method: "records", in_app: false, gem: "activerecord" },
        { file: "gems/actionpack-8.0.1/lib/abstract_controller/base.rb", line: 226, method: "process_action", in_app: false, gem: "actionpack" } ]
    end

    def request
      { url: "https://shop.acme.dev/checkout", method: "POST", format: "text/html",
        request_id: SecureRandom.uuid, remote_ip: "81.2.69.#{160 + @index}" }
    end

    def breadcrumbs
      [ { offset_ms: -412, category: "request", level: "info", message: "POST /checkout", data: {} },
        { offset_ms: -371, category: "sql", level: "debug", message: "User Load (0.6ms)", data: { sql: "SELECT \"users\".* FROM \"users\" WHERE \"id\" = $1" } },
        { offset_ms: -290, category: "http", level: "info", message: "GET api.taxjar.com/v2/rates/94107", data: { status: 200 } },
        { offset_ms: -21, category: "log", level: "warning", message: "Cart contains discontinued variant 4410", data: {} } ]
    end

    def context
      { runtime: { ruby: "3.4.1 (YJIT on)", rails: "8.0.1" }, host: "web-7f9c-2",
        process: "puma · pid 4412 · thread 23", env: { RAILS_ENV: "production" } }
    end
end

# Project-level hourly rollups, summed from the project's issue rollups.
class DemoProjectRollup
  def initialize(project)
    @project = project
  end

  def seed
    rows = sums.map { |hour, count| { project_id: @project.id, environment: environment, hour:, count: } }
    ProjectHourlyCount.insert_all(rows) if rows.any?
  end

  private
    def sums
      IssueHourlyCount.where(issue_id: @project.issues.select(:id)).group(:hour).sum(:count)
    end

    def environment
      @project.environments.first
    end
end

# Uptime monitors on .example hosts with 30 days of hourly rollups, a day of
# raw checks and incidents, all written directly: seeding never makes a request.
class DemoUptime
  MONITORS = [
    { project: "storefront", name: "Storefront home", url: "https://shop.acme.example/up", interval: 5, ms: 180 },
    { project: "storefront", name: "Checkout API", url: "https://api.acme.example/health?token=demo-only", interval: 1, ms: 95,
      outage: [ 12.minutes, nil ] },
    { project: "billing-api", name: "Billing API", url: "https://billing.acme.example/up", interval: 10, ms: 240,
      outage: [ 2.days, 25.minutes ] }
  ].freeze

  def initialize(account)
    @account = account
    @now = Time.current
  end

  # Demo monitors skip validation; fitting then applies hosted entitlements.
  def seed
    MONITORS.each { |spec| DemoMonitor.new(@account.projects.find_by!(name: spec[:project]), spec, @now).seed }
    @account.fit_uptime_monitors_to_entitlements
  end
end

class DemoMonitor
  def initialize(project, spec, now)
    @project = project
    @spec = spec
    @now = now
    started_ago, lasted = spec[:outage]
    @outage = started_ago && ((now - started_ago)..(lasted && now - started_ago + lasted))
  end

  def seed
    @monitor = create_monitor
    UptimeHourlyCount.insert_all(hourly_rows)
    UptimeCheck.insert_all(check_rows)
    UptimeIncident.insert_all([ incident_row ]) if @outage
  end

  private
    def down_now? = @outage && @outage.end.nil?

    def down_at?(time) = @outage&.cover?(time) || false

    def create_monitor
      @project.uptime_monitors.new(
        name: @spec[:name], url: @spec[:url], interval_minutes: @spec[:interval], status: down_now? ? "down" : "up",
        last_checked_at: @now - 30.seconds, last_response_time_ms: down_now? ? nil : @spec[:ms], last_http_status: down_now? ? nil : 200,
        last_error_kind: down_now? ? "timeout" : nil, down_since: down_now? ? @outage.begin : nil
      ).tap { it.save!(validate: false) }
    end

    def hourly_rows
      (0...(30 * 24)).map do |ago|
        hour = TimeSeries.align(@now, 1.hour) - ago.hours
        times = (0...60).step(@spec[:interval]).map { |minute| hour + minute.minutes }.select { it <= @now }
        up = times.count { !down_at?(it) }
        { uptime_monitor_id: @monitor.id, hour:, checks_count: times.size, up_count: up, response_time_ms_sum: up * @spec[:ms] }
      end
    end

    def check_rows
      count = 24 * 60 / @spec[:interval]
      (0...count).map do |i|
        at = @now - 30.seconds - (i * @spec[:interval]).minutes
        down = down_at?(at)
        { uptime_monitor_id: @monitor.id, checked_at: at, status: down ? "down" : "up", error_kind: down ? "timeout" : nil,
          http_status: down ? nil : 200, response_time_ms: down ? nil : @spec[:ms] + (i * 37) % 60 }
      end
    end

    def incident_row
      { uptime_monitor_id: @monitor.id, started_at: @outage.begin, resolved_at: @outage.end, error_kind: "timeout" }
    end
end

# Performance data for storefront production, written directly through the
# processing objects (no requests): minute and hourly rows for the last 24
# hours, hourly rows for the 6 days before, and slow-request traces.
# CheckoutsController#create has been Slower for the last hour, with an N+1
# query in its traces. Durations follow a fixed per-transaction profile.
class DemoApm
  Entry = Apm::MetricsPayload::Entry

  # [kind, name, labels, requests per minute, median ms, layer shares db/http/view]
  TRANSACTIONS = [
    [ "web", "CheckoutsController#create", { http_method: "POST", route: "/checkout", source_file: "app/controllers/checkouts_controller.rb" }, 42, 260, [ 0.45, 0.3, 0.12 ] ],
    [ "web", "ProductsController#show", { http_method: "GET", route: "/products/:slug", source_file: "app/controllers/products_controller.rb" }, 380, 70, [ 0.35, 0.0, 0.45 ] ],
    [ "web", "ProductsController#index", { http_method: "GET", route: "/products", source_file: "app/controllers/products_controller.rb" }, 110, 140, [ 0.4, 0.0, 0.42 ] ],
    [ "web", "CartsController#show", { http_method: "GET", route: "/cart", source_file: "app/controllers/carts_controller.rb" }, 190, 55, [ 0.3, 0.0, 0.5 ] ],
    [ "web", "CartItemsController#create", { http_method: "POST", route: "/cart/items", source_file: "app/controllers/cart_items_controller.rb" }, 60, 110, [ 0.55, 0.0, 0.1 ] ],
    [ "web", "PaymentsController#confirm", { http_method: "POST", route: "/payments/confirm", source_file: "app/controllers/payments_controller.rb" }, 18, 820, [ 0.12, 0.78, 0.04 ] ],
    [ "web", "SearchController#index", { http_method: "GET", route: "/search", source_file: "app/controllers/search_controller.rb" }, 75, 310, [ 0.7, 0.0, 0.15 ] ],
    [ "web", "Api::V1::InventoryController#show", { http_method: "GET", route: "/api/v1/inventory/:sku", source_file: "app/controllers/api/v1/inventory_controller.rb" }, 140, 35, [ 0.6, 0.0, 0.05 ] ],
    [ "web", "SessionsController#create", { http_method: "POST", route: "/session", source_file: "app/controllers/sessions_controller.rb" }, 9, 240, [ 0.1, 0.0, 0.1 ] ],
    [ "job", "Orders::PlaceJob", { adapter: "sidekiq", queue: "critical", source_file: "app/jobs/orders/place_job.rb" }, 30, 520, [ 0.5, 0.3, 0.0 ] ],
    [ "job", "Shipping::RatesFetcher", { adapter: "sidekiq", queue: "default", source_file: "lib/shipping/rates_fetcher.rb" }, 14, 1150, [ 0.1, 0.82, 0.0 ] ],
    [ "job", "Emails::ReceiptJob", { adapter: "sidekiq", queue: "mailers", source_file: "app/jobs/emails/receipt_job.rb" }, 30, 180, [ 0.25, 0.4, 0.25 ] ],
    [ "job", "Search::ReindexJob", { adapter: "sidekiq", queue: "low", source_file: "app/jobs/search/reindex_job.rb" }, 2, 4200, [ 0.75, 0.1, 0.0 ] ]
  ].freeze
  SLOWER = "CheckoutsController#create".freeze

  def initialize(project, environment: "production")
    @project = project
    @environment = environment
    @now = Time.current
    @registry = Apm::TransactionRegistry.new(project_id: project.id, environment:, now: @now)
  end

  def seed
    recent = recent_entries
    ids = @registry.ids_for(recent, totals: true)
    total_ids = %w[web job].index_with { @registry.total_id(it) }
    recent.each_slice(2_000) { Apm::StatsUpsert.new(ids:, total_ids:).upsert(it) }
    ApmHourlyStat.insert_all(older_hour_rows(ids, total_ids))
    DemoApmTraces.new(@project, @environment, ids, @now).seed
  end

  private
    def minute_now = TimeSeries.align(@now, 1.minute)

    # Every minute of the last 24 hours.
    def recent_entries
      (0...(24 * 60)).flat_map do |ago|
        minute = minute_now - ago.minutes
        TRANSACTIONS.map { |spec| entry(spec, minute, slow: spec[1] == SLOWER && ago < 60) }
      end
    end

    def entry((kind, name, labels, rate, median, shares), minute, slow: false)
      count = [ (rate * daily_curve(minute)).round, 1 ].max
      Entry.new(kind:, name:, labels:, minute:,
                distribution: DemoApmProfile.new(median * (slow ? 3.2 : 1), shares, slow:).distribution(count, failed: failures(count, minute, slow), job: kind == "job"))
    end

    def daily_curve(time) = 0.65 + (0.35 * Math.sin((time.hour - 9) * Math::PI / 12))

    def failures(count, minute, slow) = (slow || (minute.to_i / 60) % 17 == 0) ? (count * 0.03).ceil : 0

    # Hourly rows only for the 6 days before the last 24 hours.
    def older_hour_rows(ids, total_ids)
      first_hour = TimeSeries.align(minute_now - 24.hours, 1.hour)
      (1..(6 * 24)).flat_map { |ago| hour_rows(first_hour - ago.hours, ids, total_ids) }
    end

    def hour_rows(hour, ids, total_ids)
      by_id = Hash.new { Apm::Distribution.empty }
      TRANSACTIONS.each do |spec|
        distribution = DemoApmProfile.new(spec[4], spec[5]).distribution((spec[3] * daily_curve(hour) * 60).round, failed: 1, job: spec[0] == "job")
        by_id[ids.fetch([ spec[0], spec[1] ])] += distribution
        by_id[total_ids.fetch(spec[0])] += distribution
      end
      by_id.map { |id, distribution| Apm::StatsUpsert.row(id, :hour, hour, distribution) }
    end
end

# A fixed, log-normal-ish spread of durations around a median, as shares of
# the gs-v1 buckets, with each bucket's time split by layer shares.
class DemoApmProfile
  SPREAD = { -2 => 0.04, -1 => 0.18, 0 => 0.4, 1 => 0.22, 2 => 0.1, 3 => 0.04, 4 => 0.02 }.freeze

  def initialize(median_ms, shares, slow: false)
    @median = median_ms
    @shares = slow ? [ 0.62, 0.22, 0.06 ] : shares
  end

  def distribution(count, failed:, job:)
    buckets = bucket_counts(count).map { |index, n| bucket(index, n) }
    Apm::Distribution.from_buckets(count:, failed: [ failed, count ].min, duration_ms: buckets.sum { it.drop(2).sum },
                                   buckets:, queue_wait: job ? [ [ 11, count ] ] : [], queue_wait_ms: job ? count * 48.0 : 0.0)
  end

  private
    def bucket_counts(count)
      center = Apm::Histogram.index(@median)
      counts = SPREAD.to_h { |offset, share| [ (center + offset).clamp(0, Apm::Histogram::LAST), (count * share).floor ] }
      counts[center] += count - counts.values.sum
      counts.select { |_, n| n.positive? }
    end

    def bucket(index, count)
      bounds = Apm::Histogram::BOUNDS_MS
      mean = index.zero? ? 0.5 : Math.sqrt(bounds[index - 1] * (bounds[index] || bounds.last * 1.4))
      total = mean * count
      db, http, view = @shares.map { total * it }
      [ index, count, db, http, view, [ total - db - http - view, 0.0 ].max ]
    end
end

# Slow-request traces: one per minute for the slowest transactions in the
# last 30 minutes, and the 3 slowest per earlier hour of the last day.
class DemoApmTraces
  TRACED = [ "CheckoutsController#create", "SearchController#index", "PaymentsController#confirm", "Orders::PlaceJob" ].freeze

  def initialize(project, environment, ids, now)
    @project = project
    @ids = ids
    @now = now
    @normalizer = Apm::TraceNormalizer.new
    @error_uuid = project.occurrences.joins(:issue).where(issues: { transaction_name: "CheckoutsController#create" })
      .order(:received_at).last&.uuid
  end

  def seed
    traces = TRACED.flat_map { |name| minutes.map { trace(name, it) } }
    Apm::TraceUpsert.new(project_id: @project.id, ids: @ids, now: @now).upsert(traces)
  end

  private
    def minutes
      current = TimeSeries.align(@now, 1.minute) - 1.minute
      (0...30).map { current - it.minutes } + (1..23).flat_map { |ago| [ 7, 23, 41 ].map { TimeSeries.align(@now, 1.hour) - ago.hours + it.minutes } }
    end

    def trace(name, minute)
      spec = DemoApm::TRANSACTIONS.find { it[1] == name }
      slow = name == DemoApm::SLOWER && minute > @now - 1.hour
      duration = spec[4] * (slow ? 9.5 : 3.4) * (1 + ((minute.to_i / 60) % 7) / 10.0)
      @normalizer.normalize(DemoApmTrace.new(spec, minute, duration, slow:, error_uuid: (@error_uuid if slow && minute.min % 9 == 0)).to_h)
    end
end

# One trace in the traces payload shape (docs/INGEST_API.md), fictional data.
class DemoApmTrace
  def initialize(spec, minute, duration, slow:, error_uuid:)
    @kind, @name, @labels, _, _, @shares = spec
    @minute = minute
    @duration = duration.round(1)
    @slow = slow
    @error_uuid = error_uuid
  end

  def to_h
    started_at = @minute + 8.114.seconds
    { "id" => Apm::TraceId.generate(started_at), "kind" => @kind, "name" => @name, "method" => @labels[:http_method],
      "route" => @labels[:route], "queue" => @labels[:queue], "adapter" => @labels[:adapter],
      "minute" => @minute.utc.iso8601, "started_at" => started_at.utc.iso8601(3), "duration_ms" => @duration,
      **layers, "status" => status, "failed" => @error_uuid.present?, "error_event_id" => @error_uuid,
      "request" => (web? ? { "method" => @labels[:http_method], "path" => @labels[:route].sub(":slug", "linen-shirt").sub(":sku", "SKU-4410"),
                             "request_id" => SecureRandom.uuid } : nil),
      "job" => (web? ? nil : { "adapter" => @labels[:adapter], "queue" => @labels[:queue], "queue_wait_ms" => 48.0, "executions" => 1 }),
      "host" => "web-#{@minute.min % 3 + 1}", "process" => web? ? "Puma worker #{@minute.min % 4}" : "Sidekiq",
      "runtime" => { "ruby" => "3.4.1", "rails" => "8.0.2" }, "gc" => { "time_ms" => 14.0, "count" => 3 },
      "allocations" => 1_400_000, "spans_dropped" => 0, "spans" => DemoApmSpans.new(@name, @duration, layers, slow: @slow).spans }
  end

  private
    def web? = @kind == "web"

    def status
      return unless web?

      @error_uuid ? 500 : 200
    end

    def shares = @slow ? [ 0.62, 0.22, 0.06 ] : @shares

    def layers
      db, http, view = shares.map { (@duration * it).round(1) }
      { "db_ms" => db, "http_ms" => http, "view_ms" => view, "ruby_ms" => (@duration - db - http - view).round(1) }
    end
end

# The spans of a demo trace: a user lookup, the checkout N+1 (when slow), a
# tax API call, a render and an enqueue, laid out along the request.
class DemoApmSpans
  N_PLUS_ONE_CONTEXT = [ "def total_cents", "  items.sum do |item|", "    item.product.price_cents * item.quantity",
                         "  end", "end" ].freeze

  def initialize(name, duration, layers, slow:)
    @name = name
    @duration = duration
    @layers = layers
    @slow = slow
  end

  def spans
    [ user_load, (n_plus_one if @slow), (http_call if @layers["http_ms"].positive?),
      (render if @layers["view_ms"].positive?), enqueue ].compact
  end

  private
    def user_load
      { "type" => "sql", "offset_ms" => 12.1, "duration_ms" => 1.4, "name" => "User Load", "rows" => 1,
        "sql" => %(SELECT "users".* FROM "users" WHERE "users"."id" = $1 LIMIT $2) }
    end

    def n_plus_one
      total = (@layers["db_ms"] * 0.9).round(1)
      { "type" => "sql", "offset_ms" => 40.1, "duration_ms" => total, "span_ms" => (total * 1.03).round(1), "count" => 38,
        "rows" => 38, "name" => "Product Load", "sql" => %(SELECT "products".* FROM "products" WHERE "products"."id" = $1 LIMIT $2),
        "call_site" => { "file" => "app/services/cart_total.rb", "line" => 27, "method" => "total_cents",
                         "context" => { "start_line" => 25, "lines" => N_PLUS_ONE_CONTEXT } } }
    end

    def http_call
      { "type" => "http", "offset_ms" => (@duration * 0.45).round(1), "duration_ms" => @layers["http_ms"], "method" => "POST",
        "host" => "api.taxjar.example", "path" => "/v2/taxes", "status" => 200 }
    end

    def render
      { "type" => "view", "offset_ms" => (@duration * 0.86).round(1), "duration_ms" => @layers["view_ms"],
        "template" => "#{@name.split("#").first.delete_suffix("Controller").underscore}/#{@name.split("#").last}.html.erb" }
    end

    def enqueue
      { "type" => "enqueue", "offset_ms" => (@duration * 0.98).round(1), "duration_ms" => 1.2, "job" => "Emails::ReceiptJob", "queue" => "mailers" }
    end
end

DemoSeeds.new.run
