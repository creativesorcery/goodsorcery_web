import { Controller } from "@hotwired/stimulus"

// all / sql / http / log chips filter the breadcrumbs timeline. The final
// coral "error" node is not an item target, so it always stays visible.
//
// <section data-controller="breadcrumb-filter">
//   <button type="button" aria-pressed="true" data-breadcrumb-filter-target="chip"
//           data-breadcrumb-filter-category-param="all" data-action="breadcrumb-filter#filter">all 4</button>
//   <li data-breadcrumb-filter-target="item" data-category="sql">…</li>
// </section>
export default class extends Controller {
  static targets = ["chip", "item"]

  filter({ currentTarget, params: { category } }) {
    this.chipTargets.forEach((chip) => chip.setAttribute("aria-pressed", chip === currentTarget))
    this.itemTargets.forEach((item) => {
      item.hidden = category !== "all" && item.dataset.category !== category
    })
  }
}
