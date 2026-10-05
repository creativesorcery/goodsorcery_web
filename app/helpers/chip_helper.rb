module ChipHelper
  CHIP_TONES = {
    neutral: "chip",
    coral: "chip chip-coral",
    lilac: "chip chip-lilac",
    mint: "chip chip-mint",
    iris: "chip chip-iris",
    muted: "chip chip-muted"
  }.freeze

  LEVEL_TONES = { "fatal" => :coral, "error" => :neutral, "warning" => :lilac, "info" => :iris }.freeze

  STATUS_CHIPS = {
    "resolved" => [ "Resolved", :mint ],
    "ignored" => [ "Ignored", :muted ]
  }.freeze

  # chip("Spiking", tone: :coral, dot: true) → <span class="chip chip-coral"><span class="coral-dot …"></span>Spiking</span>
  def chip(text, tone: :neutral, dot: false, mono: false, small: false)
    classes = [ CHIP_TONES.fetch(tone.to_sym), ("font-mono" if mono), ("chip-sm" if small) ]
    tag.span safe_join([ (tag.span(class: "coral-dot w-1.5 h-1.5") if dot), text ].compact), class: classes.compact.join(" ")
  end

  # "New · unresolved" (coral, pulsing), "↺ Regressed" (lilac), "Resolved" (mint), "Ignored" (muted), "Unresolved".
  def issue_status_chip(issue)
    label, tone = issue_status_label(issue)
    chip label, tone:, dot: issue.new?
  end

  def level_chip(level)
    chip level.to_s, tone: LEVEL_TONES.fetch(level.to_s, :neutral), mono: true
  end

  private
    def issue_status_label(issue)
      return [ "New · unresolved", :coral ] if issue.new?
      return [ "↺ Regressed", :lilac ] if issue.regressed?

      STATUS_CHIPS.fetch(issue.status.to_s, [ "Unresolved", :neutral ])
    end
end
