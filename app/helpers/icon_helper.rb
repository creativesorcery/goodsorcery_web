# Line icons from the design shell (24×24, 1.6 stroke). Each icon is a list of
# [element, attributes] pairs so no markup string is ever marked html_safe.
module IconHelper
  DOT = { fill: "currentColor" }.freeze

  ICONS = {
    projects: [ [ :path, { d: "M3 7l9-4 9 4-9 4-9-4z" } ], [ :path, { d: "M3 12l9 4 9-4" } ], [ :path, { d: "M3 17l9 4 9-4" } ] ],
    issues: [ [ :circle, { cx: 12, cy: 12, r: 9 } ], [ :path, { d: "M12 7v6" } ], [ :circle, { cx: 12, cy: 16.5, r: 0.6, **DOT } ] ],
    alerts: [ [ :path, { d: "M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9" } ], [ :path, { d: "M10 21h4" } ] ],
    uptime: [ [ :path, { d: "M3 12h4l3-8 4 16 3-8h4" } ] ],
    settings: [ [ :circle, { cx: 12, cy: 12, r: 3 } ],
                [ :path, { d: "M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" } ] ],
    book: [ [ :path, { d: "M4 4h10a4 4 0 0 1 4 4v12H8a4 4 0 0 1-4-4z" } ], [ :path, { d: "M18 8h2v12" } ] ],
    search: [ [ :circle, { cx: 11, cy: 11, r: 7 } ], [ :path, { d: "m20 20-3.5-3.5" } ] ],
    filter: [ [ :path, { d: "M3 5h18M6 12h12M10 19h4" } ] ],
    chevron_updown: [ [ :path, { d: "m8 9 4-4 4 4M8 15l4 4 4-4" } ] ],
    chevron_down: [ [ :path, { d: "m6 9 6 6 6-6" } ] ],
    check: [ [ :path, { d: "M5 12.5l4.5 4.5L19 7.5" } ] ],
    plus: [ [ :path, { d: "M12 5v14M5 12h14" } ] ],
    external: [ [ :path, { d: "M14 4h6v6" } ], [ :path, { d: "M20 4l-9 9" } ], [ :path, { d: "M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" } ] ],
    sign_out: [ [ :path, { d: "M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3" } ], [ :path, { d: "M10 17l-5-5 5-5" } ], [ :path, { d: "M5 12h11" } ] ]
  }.freeze

  def icon(name, classes: "w-[17px] h-[17px]")
    shapes = ICONS.fetch(name.to_sym).map { |element, attributes| tag.public_send(element, **attributes) }
    tag.svg safe_join(shapes), viewBox: "0 0 24 24", class: "#{classes} shrink-0", fill: "none",
      stroke: "currentColor", "stroke-width": 1.6, "stroke-linecap": "round", "stroke-linejoin": "round",
      "aria-hidden": true, focusable: false
  end
end
