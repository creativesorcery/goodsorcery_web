import { Controller } from "@hotwired/stimulus"

// Copies the text of the `source` target (or a literal `text` value) and shows
// "Copied ✓" on the label for 1.2 s. Descendants marked data-clipboard-skip
// (e.g. a "$ " prompt) are left out of the copied text.
//
// <div data-controller="clipboard">
//   <pre data-clipboard-target="source"><span data-clipboard-skip>$ </span>bundle add goodsorcery</pre>
//   <button type="button" data-action="clipboard#copy">Copy</button>
// </div>
//
// <button type="button" data-controller="clipboard" data-clipboard-text-value="GS-1042"
//         data-action="clipboard#copy">Copy short ID</button>
export default class extends Controller {
  static targets = ["source", "label"]
  static values = { text: String, copied: { type: String, default: "Copied ✓" } }

  disconnect() {
    this.restoreLabel()
  }

  async copy(event) {
    event.preventDefault()
    try {
      await navigator.clipboard.writeText(this.text)
      this.flashLabel(event.currentTarget)
    } catch {
      this.flashLabel(event.currentTarget, "Copy failed")
    }
  }

  get text() {
    if (this.hasTextValue) return this.textValue
    const source = this.sourceTarget
    if (source.matches("input, textarea")) return source.value

    const copy = source.cloneNode(true)
    copy.querySelectorAll("[data-clipboard-skip]").forEach((node) => node.remove())
    return copy.textContent.trim()
  }

  flashLabel(button, message = this.copiedValue) {
    this.restoreLabel()
    this.labelElement = this.hasLabelTarget ? this.labelTarget : button
    this.originalLabel = this.labelElement.textContent
    this.labelElement.textContent = message
    this.timeout = setTimeout(() => this.restoreLabel(), 1200)
  }

  restoreLabel() {
    clearTimeout(this.timeout)
    if (this.labelElement) this.labelElement.textContent = this.originalLabel
    this.labelElement = null
  }
}
