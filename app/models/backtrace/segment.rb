# A slice of a Backtrace: either a single app frame, or a run of consecutive
# framework/library frames that the issue page folds into one row.
class Backtrace::Segment
  PACKAGE_NAMES_SHOWN = 3

  attr_reader :frames

  def initialize(frames)
    @frames = frames
    @expanded = false
  end

  def app? = frames.first.app?

  def framework? = !app?

  # The single frame of an app segment.
  def frame = frames.first

  def size = frames.size

  # The top app frame is expanded with code context and locals.
  def expand! = @expanded = true

  def expanded? = @expanded

  def package_names = frames.filter_map(&:package).uniq

  # "activesupport, activerecord" or "actionpack, rack, puma…"
  def package_summary
    names = package_names
    summary = names.first(PACKAGE_NAMES_SHOWN).join(", ")
    names.size > PACKAGE_NAMES_SHOWN ? "#{summary}…" : summary
  end
end
