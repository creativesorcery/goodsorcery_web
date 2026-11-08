import { Controller } from "@hotwired/stimulus"

// No pinch-zoom (the user's call). The viewport meta (maximum-scale=1,
// user-scalable=no) and `touch-action: pan-x pan-y` on <html> cover most
// browsers; iOS Safari ignores both for pinches, so its own gesture events
// are cancelled here. Fields are 16px on touch screens, so iOS never needs
// to zoom in on focus either.
//
// <html data-controller="zoom-lock">
export default class extends Controller {
  connect() {
    this.cancel = (event) => event.preventDefault()
    for (const type of ["gesturestart", "gesturechange"]) document.addEventListener(type, this.cancel, { passive: false })
  }

  disconnect() {
    for (const type of ["gesturestart", "gesturechange"]) document.removeEventListener(type, this.cancel)
  }
}
