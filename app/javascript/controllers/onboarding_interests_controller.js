import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["submit", "interest", "unknown"];

  connect() {
    this.refresh();
  }

  refresh() {
    if (!this.hasSubmitTarget) return;
    const anyChecked =
      this.element.querySelectorAll("input[type=checkbox]:checked").length > 0;
    this.submitTarget.disabled = !anyChecked;
    this.submitTarget.classList.toggle("action-btn--disabled", !anyChecked);
  }

  toggle(event) {
    const target = event.target;
    if (!target || target.type !== "checkbox" || !target.checked) {
      this.refresh();
      return;
    }

    if (this.hasUnknownTarget && target === this.unknownTarget) {
      this.interestTargets.forEach((cb) => (cb.checked = false));
    } else if (this.hasUnknownTarget && this.interestTargets.includes(target)) {
      this.unknownTarget.checked = false;
    }

    this.refresh();
  }
}
