import { Controller } from "@hotwired/stimulus"

// Issue list selection and the floating bulk-action bar.
//
// <div data-controller="bulk-selection">
//   <input type="checkbox" data-bulk-selection-target="all" data-action="bulk-selection#toggleAll">
//   <input type="checkbox" form="bulk_triage" name="issue_ids[]" value="42"
//          data-bulk-selection-target="checkbox" data-action="bulk-selection#toggle">
//   <div data-bulk-selection-target="bar" hidden>… <span data-bulk-selection-target="count"></span> selected …</div>
// </div>
//
// Selected ids live in a Set, so a row frame that is live-reloaded (or a page
// appended by "load more") comes back with its checkbox still ticked.
export default class extends Controller {
  static targets = ["checkbox", "all", "bar", "count"]

  connect() {
    this.selected = new Set()
    this.render()
  }

  toggle(event) {
    this.remember(event.target)
    this.render()
  }

  toggleAll(event) {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = event.target.checked
      this.remember(checkbox)
    })
    this.render()
  }

  clear() {
    this.selected.clear()
    this.checkboxTargets.forEach((checkbox) => (checkbox.checked = false))
    this.render()
  }

  // Fires for re-rendered row frames and newly loaded pages alike.
  checkboxTargetConnected(checkbox) {
    checkbox.checked = this.selected?.has(checkbox.value) ?? false
    this.render()
  }

  checkboxTargetDisconnected() {
    this.render()
  }

  remember(checkbox) {
    checkbox.checked ? this.selected.add(checkbox.value) : this.selected.delete(checkbox.value)
  }

  // The count is what will actually be submitted: ticked boxes on screen.
  render() {
    if (!this.selected) return

    const checked = this.checkboxTargets.filter((checkbox) => checkbox.checked).length
    if (this.hasBarTarget) this.barTarget.hidden = checked === 0
    if (this.hasCountTarget) this.countTarget.textContent = checked
    if (this.hasAllTarget) this.renderAll(checked)
  }

  renderAll(checked) {
    const total = this.checkboxTargets.length
    this.allTarget.checked = total > 0 && checked === total
    this.allTarget.indeterminate = checked > 0 && checked < total
  }
}
