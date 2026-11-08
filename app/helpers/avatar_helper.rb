module AvatarHelper
  AVATAR_BOXES = { sm: "w-6 h-6", md: "w-7 h-7", lg: "w-8 h-8" }.freeze
  AVATAR_TEXT = { sm: "text-[10px]", md: "text-[10.5px]", lg: "text-[12px]" }.freeze
  AVATAR_TONES = [
    "text-iris-300 ring-iris-500/30",
    "text-mint-300 ring-mint-400/30",
    "text-lilac-300 ring-lilac-400/30",
    "text-coral-300 ring-coral-500/30"
  ].freeze

  TILE_SIZES = {
    sm: "w-6 h-6 rounded-md text-[11px] font-bold",
    md: "w-8 h-8 rounded-lg font-display text-[15px]",
    lg: "w-10 h-10 rounded-xl font-display text-[18px]"
  }.freeze
  TILE_TONES = { "iris" => "bg-iris-100", "coral" => "bg-coral-100", "lilac" => "bg-lilac-100", "mint" => "bg-mint-100" }.freeze
  LISTENING_TILE = "border border-dashed border-iris-500/40 text-iris-300".freeze

  # Ring avatar with initials, tinted deterministically by name.
  def initials_avatar(name, size: :md)
    classes = "#{AVATAR_BOXES.fetch(size)} #{AVATAR_TEXT.fetch(size)} #{avatar_tone(name)}"
    tag.span avatar_initials(name), title: name, class: "#{classes} shrink-0 rounded-full bg-paper-700 grid place-items-center font-medium ring-1"
  end

  # Dashed circle for "unassigned".
  def empty_avatar(size: :md)
    tag.span title: "Unassigned", class: "#{AVATAR_BOXES.fetch(size)} inline-block shrink-0 rounded-full border border-dashed border-paper-600"
  end

  # Letter tile tinted by project.color; listening projects get a dashed iris outline.
  def project_tile(project, size: :md)
    tone = project.listening? ? LISTENING_TILE : "#{TILE_TONES.fetch(project.color.to_s, 'bg-iris-100')} text-ink-50"
    tag.span project.name.to_s.first.to_s.upcase, "aria-hidden": true,
      class: "#{TILE_SIZES.fetch(size)} #{tone} shrink-0 grid place-items-center"
  end

  private
    def avatar_initials(name)
      name.to_s.split.first(2).map { |word| word.first.upcase }.join.presence || "?"
    end

    def avatar_tone(name)
      AVATAR_TONES[name.to_s.sum % AVATAR_TONES.size]
    end
end
