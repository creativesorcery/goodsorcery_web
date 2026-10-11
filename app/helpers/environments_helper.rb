# Environment names drawn in their tone (EnvironmentTone): coral for
# production, lilac for staging, muted for local and test, iris otherwise.
# Class names are complete literals so Tailwind sees them.
module EnvironmentsHelper
  TEXT_TONES = { coral: "text-coral-300", lilac: "text-lilac-300", muted: "text-ink-400", iris: "text-iris-300" }.freeze
  DOT_TONES = { coral: "bg-coral-500", lilac: "bg-lilac-400", muted: "bg-paper-500", iris: "bg-iris-400" }.freeze
  BAR_TONES = {
    coral: "border-coral-500/30 bg-coral-500/10 text-coral-300",
    lilac: "border-lilac-400/30 bg-lilac-400/10 text-lilac-300",
    muted: "border-paper-700 bg-paper-850 text-ink-300",
    iris: "border-iris-500/20 bg-iris-500/10 text-iris-300"
  }.freeze
  CHART_COLORS = { coral: ChartHelper::CORAL, lilac: ChartHelper::LILAC, muted: ChartHelper::PAPER, iris: ChartHelper::IRIS }.freeze

  def environment_tone(name)
    EnvironmentTone.of(name)
  end

  # chip("production", tone: :coral) and friends.
  def environment_chip(name, small: false)
    chip name, tone: environment_tone(name), small:
  end

  # A small round swatch, for menus, switches and key rows.
  def environment_dot(name)
    tag.span class: "inline-block w-2 h-2 shrink-0 rounded-full #{DOT_TONES.fetch(environment_tone(name))}", "aria-hidden": true
  end

  # The bare name in its tone, for running text such as "12:04 · staging · v42".
  def environment_text(name)
    tag.span name, class: TEXT_TONES.fetch(environment_tone(name))
  end

  # Border, background and text classes for a full-width strip in the tone.
  def environment_bar_classes(name)
    BAR_TONES.fetch(environment_tone(name))
  end

  # Hex colour for SVG charts and sparklines.
  def environment_color(name)
    CHART_COLORS.fetch(environment_tone(name))
  end
end
