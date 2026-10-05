import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a flash message after `delay` ms (0 keeps it until dismissed).
//
// <div data-controller="flash" data-flash-delay-value="5000">
//   Saved. <button type="button" data-action="flash#dismiss">×</button>
// </div>
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    if (this.delayValue > 0) this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.remove()
  }
}
