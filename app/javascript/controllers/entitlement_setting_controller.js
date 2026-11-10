import { Controller } from "@hotwired/stimulus"

// Staff › Accounts › Entitlements: greys out and disables one entitlement's
// custom fields unless "Custom" is chosen (Default, or No limit for a cap). The server ignores those fields
// then anyway; without JavaScript they just stay editable.
//
// <div data-controller="entitlement-setting">
//   <input type="radio" value="default" data-action="entitlement-setting#update">
//   <input type="radio" value="custom" data-entitlement-setting-target="custom" data-action="entitlement-setting#update">
//   <fieldset data-entitlement-setting-target="fields">…</fieldset>
// </div>
export default class extends Controller {
  static targets = ["custom", "fields"]

  connect() {
    this.update()
  }

  update() {
    const custom = this.customTarget.checked
    this.fieldsTarget.disabled = !custom
    this.fieldsTarget.classList.toggle("opacity-50", !custom)
  }
}
