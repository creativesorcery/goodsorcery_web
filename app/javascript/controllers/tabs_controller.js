import { Controller } from "@hotwired/stimulus"

// Client-side tabs (install snippets, issue context tabs). Each tab points at its
// panel with aria-controls; the selected tab has aria-selected="true".
//
// <section data-controller="tabs">
//   <div role="tablist">
//     <button type="button" class="tab" role="tab" aria-selected="true" aria-controls="ctx-request"
//             data-tabs-target="tab" data-action="tabs#select">Request</button>
//     <button type="button" class="tab" role="tab" aria-selected="false" aria-controls="ctx-params"
//             data-tabs-target="tab" data-action="tabs#select">Params</button>
//   </div>
//   <div id="ctx-request" role="tabpanel" data-tabs-target="panel">…</div>
//   <div id="ctx-params" role="tabpanel" data-tabs-target="panel" hidden>…</div>
// </section>
export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    event.preventDefault()
    this.show(event.currentTarget.getAttribute("aria-controls"))
  }

  show(panelId) {
    this.tabTargets.forEach((tab) => {
      tab.setAttribute("aria-selected", tab.getAttribute("aria-controls") === panelId)
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.id !== panelId
    })
  }
}
