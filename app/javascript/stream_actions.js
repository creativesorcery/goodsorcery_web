import { Turbo } from "@hotwired/turbo-rails"

// <turbo-stream action="reload_frame" target="issue_1_row" src="/projects/x/issues/GS-1/row">
// Live updates carry only a pointer (frame id + URL); each browser re-fetches the
// fragment with its own session, so no captured data ever travels over Action Cable.
// A frame already showing the same resource reloads its own src, so a viewer's
// choice inside it (e.g. ?period=7d on a chart or summary) survives live reloads.
const samePath = (frameSrc, src) =>
  frameSrc && new URL(frameSrc, document.baseURI).pathname === new URL(src, document.baseURI).pathname

Turbo.StreamActions.reload_frame = function () {
  const src = this.getAttribute("src")
  if (!src) return

  this.targetElements.forEach((frame) => {
    samePath(frame.getAttribute("src"), src) ? frame.reload() : frame.setAttribute("src", src)
  })
}
