# The string cleaning applied to every captured trace string
# (docs/ARCHITECTURE.md §13.5): capped, scrubbed of secrets by
# Ingest::Scrubber; paths lose their query string and fragment, hosts their
# user:pass@ part, files are made app-relative, SQL is re-normalised.
class Apm::TraceCleaner
  def initialize(scrubber: Ingest::Scrubber.new)
    @scrubber = scrubber
    @sql_scrub = Apm::SqlScrub.new(scrubber:)
    @paths = Ingest::PathNormalizer.new
  end

  def text(value, max)
    @scrubber.scrub_text(value).first(max) if value.is_a?(String)
  end

  def path(value)
    text(value.split(/[?#]/, 2).first.to_s, Apm::Limits::PATH) if value.is_a?(String)
  end

  def host(value)
    text(value.sub(/\A[^@\/]*@/, ""), Apm::Limits::HOST) if value.is_a?(String)
  end

  def file(value)
    text(@paths.normalize(value), Apm::Limits::FILE)
  end

  def sql(value)
    @sql_scrub.scrub(value) if value.is_a?(String)
  end
end
