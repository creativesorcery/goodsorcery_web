# A slice of a Backtrace: either a single app frame, or a run of consecutive
# framework/gem frames that the issue page folds into one row.
class Backtrace::Segment
  GEM_NAMES_SHOWN = 3

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

  def gem_names = frames.filter_map(&:gem_name).uniq

  # "activesupport, activerecord" or "actionpack, rack, puma…"
  def gem_summary
    names = gem_names
    summary = names.first(GEM_NAMES_SHOWN).join(", ")
    names.size > GEM_NAMES_SHOWN ? "#{summary}…" : summary
  end
end
