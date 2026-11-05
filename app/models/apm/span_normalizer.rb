# Allow-lists and caps one trace span (docs/INGEST_API.md › Traces payload):
# the common timing fields, then the fields of its type. Unknown types and
# malformed spans become nil and are dropped by Apm::TraceNormalizer.
class Apm::SpanNormalizer
  include Apm::JsonShape

  FIELDS = { "sql" => :sql_fields, "http" => :http_fields, "view" => :view_fields, "enqueue" => :enqueue_fields }.freeze

  def initialize(cleaner)
    @cleaner = cleaner
  end

  def normalize(span)
    fields = span.is_a?(Hash) && FIELDS[span["type"]]
    return unless fields && number?(span["duration_ms"])

    timing(span).merge(send(fields, span)).compact
  end

  private
    def timing(span)
      grouped = integer?(span["count"], min: 2)
      { "type" => span["type"], "offset_ms" => number?(span["offset_ms"]) ? span["offset_ms"] : 0,
        "duration_ms" => span["duration_ms"], "count" => (span["count"] if grouped),
        "span_ms" => (span["span_ms"] if grouped && number?(span["span_ms"])) }
    end

    def sql_fields(span)
      { "sql" => @cleaner.sql(span["sql"]), "name" => @cleaner.text(span["name"], Apm::Limits::SPAN_NAME),
        "rows" => (span["rows"] if integer?(span["rows"], min: 0)), "call_site" => call_site(span["call_site"]) }
    end

    def http_fields(span)
      { "method" => text(span["method"], Apm::Limits::HTTP_METHOD)&.upcase, "host" => @cleaner.host(span["host"]),
        "path" => @cleaner.path(span["path"]), "status" => (span["status"] if integer?(span["status"], min: 0, max: 999)) }
    end

    def view_fields(span)
      { "template" => @cleaner.text(span["template"], Apm::Limits::TEMPLATE) }
    end

    def enqueue_fields(span)
      { "job" => text(span["job"], Apm::Limits::NAME), "queue" => text(span["queue"], Apm::Limits::QUEUE) }
    end

    def call_site(site)
      return unless site.is_a?(Hash) && site["file"].is_a?(String)

      { "file" => @cleaner.file(site["file"]), "line" => (site["line"] if integer?(site["line"], min: 0)),
        "method" => text(site["method"], Apm::Limits::METHOD_NAME), "context" => context(site["context"]) }.compact
    end

    def context(context)
      return unless context.is_a?(Hash) && context["lines"].is_a?(Array) && integer?(context["start_line"], min: 0)

      lines = context["lines"].first(Apm::Limits::CONTEXT_LINES).map { @cleaner.text(it, Apm::Limits::CONTEXT_LINE).to_s }
      { "start_line" => context["start_line"], "lines" => lines }
    end
end
