import { Turbo } from "@hotwired/turbo-rails"

// <turbo-stream action="reload_frame" target="issue_1_row" src="/projects/x/issues/GS-1/row">
// Live updates carry only a pointer (frame id + URL); each browser re-fetches the
// fragment with its own session, so no captured data ever travels over Action Cable.
Turbo.StreamActions.reload_frame = function () {
  const src = this.getAttribute("src")
  this.targetElements.forEach((frame) => {
    frame.getAttribute("src") === src ? frame.reload() : frame.setAttribute("src", src)
  })
}
