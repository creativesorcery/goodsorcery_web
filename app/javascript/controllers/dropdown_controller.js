import { Controller } from "@hotwired/stimulus"

// Menus: project switcher, sort, filters, resolve split ▾, assign, user menu.
//
// <div data-controller="dropdown" class="relative">
//   <button type="button" data-dropdown-target="button" data-action="dropdown#toggle"
//           aria-haspopup="true" aria-expanded="false">Sort ▾</button>
//   <div data-dropdown-target="menu" class="menu right-0" hidden>…links / button_to…</div>
// </div>
//
// Closes on outside click, Escape, and before Turbo caches the page.
export default class extends Controller {
  static targets = ["button", "menu"]

  connect() {
    this.closeOnOutsideClick = this.closeOnOutsideClick.bind(this)
    this.closeOnEscape = this.closeOnEscape.bind(this)
    this.close = this.close.bind(this)
    document.addEventListener("turbo:before-cache", this.close)
  }

  disconnect() {
    this.close()
    document.removeEventListener("turbo:before-cache", this.close)
  }

  toggle(event) {
    event?.preventDefault()
    this.menuTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.menuTarget.hidden = false
    this.setExpanded(true)
    document.addEventListener("click", this.closeOnOutsideClick)
    document.addEventListener("keydown", this.closeOnEscape)
  }

  close() {
    if (this.hasMenuTarget) this.menuTarget.hidden = true
    this.setExpanded(false)
    document.removeEventListener("click", this.closeOnOutsideClick)
    document.removeEventListener("keydown", this.closeOnEscape)
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEscape(event) {
    if (event.key !== "Escape") return
    this.close()
    if (this.hasButtonTarget) this.buttonTarget.focus()
  }

  setExpanded(expanded) {
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", expanded)
  }
}
