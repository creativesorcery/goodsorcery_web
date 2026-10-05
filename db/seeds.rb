# Demo data for local development: the "Acme Labs" account from the approved
# mockups with five projects, issues, occurrences, rollups, tags, affected users
# and activity. Everything is created through the models, so captured data is
# encrypted and identities are stored only as HMAC digests.
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
    { name: "billing-api", platform: "rails_api", runtime_label: "Rails 7.2 API · Ruby 3.3", issue_prefix: "BA",
      issues_sequence: 0, environments: %w[production], first_event_at: 200.days.ago, color: "iris" },
    { name: "backoffice", platform: "rails", runtime_label: "Rails 8.0 · Hotwire", issue_prefix: "BO",
      issues_sequence: 0, environments: %w[production], first_event_at: 90.days.ago, color: "mint" },
    { name: "fulfillment-workers", platform: "sidekiq", runtime_label: "Sidekiq · Rails 8.0", issue_prefix: "FW",
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
    end
    puts "Seeded Acme Labs. Sign in as #{EMAIL} / #{PASSWORD} (also jo@example.com / #{PASSWORD})"
  end

  private
    def create_people
      @account = Account.create!(name: "Acme Labs", monthly_event_quota: 1_000_000)
      @users = {
        philip: User.create!(name: "Philip Nguyen", email_address: EMAIL, password: PASSWORD),
        jo: User.create!(name: "Jo Martin", email_address: "jo@example.com", password: PASSWORD)
      }
      @account.memberships.create!(user: @users[:philip], role: :owner)
      @account.memberships.create!(user: @users[:jo], role: :member)
    end

    def seed_project(spec)
      project = @account.projects.create!(spec.slice(:name, :platform, :runtime_label, :issue_prefix, :issues_sequence, :color, :first_event_at))
      project.api_keys.update_all(created_by_id: @users[:philip].id)
      (spec[:environments] - project.environments).each { |env| project.api_keys.create!(environment: env, created_by: @users[:philip]) }
      ISSUES.fetch(spec[:name], []).each { |row| DemoIssue.new(project, row, @users).seed }
      DemoProjectRollup.new(project).seed
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
    { exception: exception, transaction: @spec[:transaction_name], request: request,
      params: { id: 4410 + @index, coupon: "FALL25", card_token: "[FILTERED]" },
      headers: { "Accept" => "text/html", "User-Agent" => "Mozilla/5.0 (iPhone) Mobile Safari", "Cookie" => "[FILTERED]" },
      session: { user_id: @person&.dig(:id), session_id: "[FILTERED]" }, user: @person || {},
      breadcrumbs: breadcrumbs, context: context, tags: { browser: "Mobile Safari", environment: "production" },
      notifier: { name: "goodsorcery-ruby", version: "0.1.0" } }.to_json
  end

  private
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

DemoSeeds.new.run
