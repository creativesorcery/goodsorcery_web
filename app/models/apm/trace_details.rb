# Read-only view of a trace's decrypted payload (docs/ARCHITECTURE.md §13.5),
# already normalised and allow-listed by Apm::TraceNormalizer. Everything
# here is captured data: render it through ERB escaping only, and never put
# it in a log, cache, job argument or exception message.
class Apm::TraceDetails
  CallSite = Data.define(:file, :line, :method_name, :start_line, :lines) do
    def self.from(hash)
      return unless hash.is_a?(Hash)

      context = hash["context"].is_a?(Hash) ? hash["context"] : {}
      new(file: hash["file"], line: hash["line"], method_name: hash["method"],
          start_line: context["start_line"], lines: Array(context["lines"]))
    end

    def location = [ file, line ].compact.join(":")
  end

  SPAN_LAYERS = { "sql" => :db, "http" => :http, "view" => :view }.freeze

  Span = Data.define(:type, :offset_ms, :duration_ms, :span_ms, :count, :rows, :name, :sql, :call_site,
                     :http_method, :host, :path, :status, :template, :job, :queue) do
    def self.from(hash)
      new(**members.without(:http_method, :call_site).index_with { hash[it.to_s] },
          http_method: hash["method"], call_site: CallSite.from(hash["call_site"]))
    end

    def calls = count || 1

    def grouped? = calls > 1

    def n_plus_one? = type == "sql" && calls >= Apm::N_PLUS_ONE_MIN

    # The bar's width on the timeline: first start to last end for a group.
    def extent_ms = span_ms || duration_ms

    def average_ms = duration_ms.to_f / calls

    def layer = SPAN_LAYERS.fetch(type, :ruby)
  end

  def initialize(payload)
    @data = payload.is_a?(String) ? JSON.parse(payload) : payload.to_h.deep_stringify_keys
  end

  # { "method", "path", "request_id" } for web requests, else nil.
  def request = @data["request"]

  # { "adapter", "queue", "queue_wait_ms", "executions" } for jobs, else nil.
  def job = @data["job"]

  def host = @data["host"]

  def process = @data["process"]

  # { "ruby", "rails" }
  def runtime = @data["runtime"] || {}

  # { "time_ms", "count" }
  def gc = @data["gc"] || {}

  def allocations = @data["allocations"]

  def spans_dropped = @data["spans_dropped"].to_i

  # In offset order.
  def spans = @spans ||= Array(@data["spans"]).map { Span.from(it) }.sort_by { it.offset_ms.to_f }

  # The N+1 groups, largest total first.
  def n_plus_one_spans = spans.select(&:n_plus_one?).sort_by { -it.duration_ms.to_f }
end
