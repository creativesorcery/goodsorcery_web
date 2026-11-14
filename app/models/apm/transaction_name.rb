# Cleans a transaction's name and labels as sent in a metrics or traces
# payload: capped strings, routes and methods as given (patterns, never real
# paths), the source file made app-relative. A client name equal to a total
# row's fixed name is counted under (other), so it can never merge into the
# app-wide histogram.
module Apm::TransactionName
  module_function

  def clean(kind, name)
    name = name.to_s.delete("\u0000").strip.first(Apm::Limits::NAME)
    name == ApmTransaction::TOTAL_NAMES[kind] ? ApmTransaction::OTHER_NAME : name
  end

  # { http_method:, route:, adapter:, queue:, source_file: }, nil where absent.
  def labels(transaction, cleaner = nil)
    web = transaction["kind"] == "web"
    { http_method: (Apm::JsonShape.text(transaction["method"], Apm::Limits::HTTP_METHOD)&.upcase if web),
      route: (Apm::JsonShape.text(transaction["route"], Apm::Limits::ROUTE) if web),
      adapter: (Apm::JsonShape.text(transaction["adapter"], Apm::Limits::ADAPTER) unless web),
      queue: (Apm::JsonShape.text(transaction["queue"], Apm::Limits::QUEUE) unless web),
      source_file: source_file(transaction["source"], cleaner) }
  end

  def source_file(source, cleaner)
    return unless source.is_a?(String)

    (cleaner || Apm::TraceCleaner.new).file(source)
  end
end
