import { Controller } from "@hotwired/stimulus"

// The sidebar as a slide-in drawer below lg (the top bar's menu button opens it).
//
// <body data-controller="drawer" data-action="keydown->drawer#keydown">
//   <div class="drawer-backdrop" data-drawer-target="backdrop" data-action="click->drawer#close" hidden></div>
//   <aside id="sidebar" class="sidebar" data-drawer-target="panel" data-action="click->drawer#closeOnLink">…</aside>
//   <button data-drawer-target="button" data-action="drawer#open" aria-controls="sidebar" aria-expanded="false">
//
// Open: the panel gets data-open (CSS slides it in), the backdrop shows, the
// page stops scrolling and focus moves into the panel and stays there (Tab
// wraps). Escape, the backdrop, the close button or following a link close it
// and focus goes back to the menu button. At lg and up the sidebar is always
// shown, so the drawer closes itself when the window grows past it.
const FOCUSABLE = "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"

export default class extends Controller {
  static targets = ["panel", "button", "backdrop"]

  connect() {
    this.desktop = window.matchMedia("(min-width: 64rem)")
    this.closeOnDesktop = () => { if (this.desktop.matches) this.close({ restoreFocus: false }) }
    this.desktop.addEventListener("change", this.closeOnDesktop)
    this.closeBeforeCache = () => this.close({ restoreFocus: false })
    document.addEventListener("turbo:before-cache", this.closeBeforeCache)
  }

  disconnect() {
    this.close({ restoreFocus: false })
    this.desktop.removeEventListener("change", this.closeOnDesktop)
    document.removeEventListener("turbo:before-cache", this.closeBeforeCache)
  }

  get isOpen() {
    return this.hasPanelTarget && this.panelTarget.hasAttribute("data-open")
  }

  open(event) {
    event?.preventDefault()
    if (this.isOpen || this.desktop.matches) return

    this.setOpen(true)
    const first = this.focusables()[0]
    first?.focus({ preventScroll: true })
  }

  close(options = {}) {
    if (!this.isOpen) return

    this.setOpen(false)
    if (options.restoreFocus !== false && this.hasButtonTarget) this.buttonTarget.focus({ preventScroll: true })
  }

  // Following a link inside the drawer closes it; Turbo then renders the next page.
  closeOnLink(event) {
    if (event.target.closest("a[href]")) this.close({ restoreFocus: false })
  }

  keydown(event) {
    if (!this.isOpen) return
    if (event.key === "Escape") {
      // An open menu inside the drawer (project switcher, user menu) closes first.
      if (this.panelTarget.querySelector(".menu:not([hidden])")) return
      event.preventDefault()
      this.close()
    } else if (event.key === "Tab") {
      this.trapFocus(event)
    }
  }

  // private

  setOpen(open) {
    this.panelTarget.toggleAttribute("data-open", open)
    if (this.hasBackdropTarget) this.backdropTarget.hidden = !open
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", open)
    document.body.classList.toggle("drawer-open", open)
  }

  trapFocus(event) {
    const items = this.focusables()
    if (items.length === 0) return

    const first = items[0]
    const last = items[items.length - 1]
    const inside = this.panelTarget.contains(document.activeElement)
    if (event.shiftKey && (document.activeElement === first || !inside)) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && (document.activeElement === last || !inside)) {
      event.preventDefault()
      first.focus()
    }
  }

  focusables() {
    return [...this.panelTarget.querySelectorAll(FOCUSABLE)].filter((element) => element.offsetParent !== null || element === document.activeElement)
  }
}
