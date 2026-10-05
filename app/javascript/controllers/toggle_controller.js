import { Controller } from "@hotwired/stimulus"

// An aria-pressed switch that shows `expanded` targets and hides `collapsed`
// targets when on (e.g. "Show framework frames").
//
// <section data-controller="toggle">
//   <button type="button" class="toggle flex items-center gap-2" aria-pressed="false"
//           data-toggle-target="switch" data-action="toggle#flip">
//     <span class="track"><span class="knob"></span></span> Show framework frames
//   </button>
//   <div data-toggle-target="collapsed">3 framework frames hidden</div>
//   <div data-toggle-target="expanded" hidden>…frames…</div>
// </section>
export default class extends Controller {
  static targets = ["switch", "expanded", "collapsed"]

  flip(event) {
    event?.preventDefault()
    this.pressed = !this.pressed
  }

  get pressed() {
    return this.switchTarget.getAttribute("aria-pressed") === "true"
  }

  set pressed(on) {
    this.switchTarget.setAttribute("aria-pressed", on)
    this.expandedTargets.forEach((element) => { element.hidden = !on })
    this.collapsedTargets.forEach((element) => { element.hidden = on })
  }
}
