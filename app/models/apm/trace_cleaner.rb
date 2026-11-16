# The string cleaning applied to every captured trace string
# (docs/ARCHITECTURE.md §13.5): null bytes dropped, scrubbed of secrets by
# Ingest::Scrubber, capped, then scrubbed and capped again; paths lose any leading scheme://user:pass@host or //host,
# their query string and fragment, hosts their user:pass@ part, files are
# made app-relative, SQL is re-normalised.
class Apm::TraceCleaner
  def initialize(scrubber: Ingest::Scrubber.new)
    @scrubber = scrubber
    @sql_scrub = Apm::SqlScrub.new(scrubber:)
    @paths = Ingest::PathNormalizer.new
  end

  # Scrubbed, cut, then scrubbed and cut again, so a cut can't expose a
  # secret the whole string hid (Ingest::Scrubber#scrub_text). Scrubbing drops
  # null bytes first: Postgres can't store them, and one can't split a secret.
  def text(value, max)
    @scrubber.scrub_text(@scrubber.scrub_text(value).first(max)).first(max) if value.is_a?(String)
  end

  ORIGIN = %r{\A(?:[a-z][a-z0-9+.-]*:)?//[^/?#]*}i

  def path(value)
    return unless value.is_a?(String)

    bare = value.split(/[?#]/, 2).first.to_s.sub(ORIGIN, "")
    text(bare.empty? ? "/" : bare, Apm::Limits::PATH)
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
