import { Controller } from "@hotwired/stimulus"

// Menus: project switcher, sort, filters, resolve split ▾, assign, user menu.
//
// <div data-controller="dropdown" class="relative">
//   <button type="button" data-dropdown-target="button" data-action="dropdown#toggle"
//           aria-haspopup="true" aria-expanded="false">Sort ▾</button>
//   <div data-dropdown-target="menu" class="menu right-0" hidden>…links / button_to…</div>
// </div>
//
// Closes on outside click, Escape, and before Turbo caches the page. An open
// menu that would poke past the side of a narrow window is nudged back in.
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
    this.keepInViewport()
    this.setExpanded(true)
    document.addEventListener("click", this.closeOnOutsideClick)
    document.addEventListener("keydown", this.closeOnEscape)
  }

  close() {
    if (this.hasMenuTarget) {
      this.menuTarget.hidden = true
      this.menuTarget.style.removeProperty("translate")
    }
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

  keepInViewport() {
    const margin = 12
    this.menuTarget.style.removeProperty("translate")
    const { left, right } = this.menuTarget.getBoundingClientRect()
    const width = document.documentElement.clientWidth
    let shift = 0
    if (left < margin) shift = margin - left
    else if (right > width - margin) shift = Math.max(width - margin - right, margin - left)
    if (shift) this.menuTarget.style.translate = `${Math.round(shift)}px 0`
  }

  setExpanded(expanded) {
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", expanded)
  }
}
