import { Controller } from "@hotwired/stimulus"

// Fills a hidden time_zone field with the browser's IANA zone on sign-up.
//
// <input type="hidden" name="signup[time_zone]" value="UTC" data-controller="timezone">
export default class extends Controller {
  connect() {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (zone) this.element.value = zone
  }
}
