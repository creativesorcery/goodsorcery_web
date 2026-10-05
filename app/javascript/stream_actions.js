import { Turbo } from "@hotwired/turbo-rails"

// <turbo-stream action="reload_frame" target="issue_1_row" src="/projects/x/issues/GS-1/row">
// Live updates carry only a pointer (frame id + URL); each browser re-fetches the
// fragment with its own session, so no captured data ever travels over Action Cable.
// A frame already showing the same resource reloads its own src, so a viewer's
// choice inside it (e.g. ?period=7d on a chart or summary) survives live reloads.
const samePath = (frameSrc, src) =>
  frameSrc && new URL(frameSrc, document.baseURI).pathname === new URL(src, document.baseURI).pathname

// <turbo-stream action="reload_rows" target="issues_project_1" src="/projects/x/rows">
// Re-fetches every issue-list row frame on screen in one request
// (src?ids=1,2,3), however many issues changed, and applies the returned
// turbo-stream replacements.
const MAX_ROWS = 200
const ROW_PREFIX = "row_issue_"

const rowIds = (list) =>
  [...list.querySelectorAll(`turbo-frame[id^="${ROW_PREFIX}"]`)].slice(0, MAX_ROWS).map((frame) => frame.id.slice(ROW_PREFIX.length))

Turbo.StreamActions.reload_rows = function () {
  const src = this.getAttribute("src")
  if (!src) return

  this.targetElements.forEach((list) => {
    const ids = rowIds(list)
    if (ids.length === 0) return

    const url = new URL(src, document.baseURI)
    url.searchParams.set("ids", ids.join(","))
    fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" }, credentials: "same-origin" })
      .then((response) => (response.ok ? response.text() : ""))
      .then((html) => html && Turbo.renderStreamMessage(html))
  })
}

Turbo.StreamActions.reload_frame = function () {
  const src = this.getAttribute("src")
  if (!src) return

  this.targetElements.forEach((frame) => {
    samePath(frame.getAttribute("src"), src) ? frame.reload() : frame.setAttribute("src", src)
  })
}
