# Collects a payload's structural errors, at most MAX messages. Messages
# name fields and positions ("minutes[0].transactions[3].count"), never
# values, so they are safe to return and log.
class Apm::ShapeErrors
  MAX = 20

  def initialize
    @messages = []
  end

  def add(message)
    @messages << message unless full?
    nil
  end

  def full? = @messages.size >= MAX

  def to_a = @messages.dup
end
