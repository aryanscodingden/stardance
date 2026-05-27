import { Controller } from "@hotwired/stimulus";

const LEVELS = [
  {
    value: "none",
    title: "Total beginner",
    description:
      "You've never really coded or built anything — and that's awesome! We'll start from the basics.",
  },
  {
    value: "little",
    title: "A little bit",
    description:
      "You've done some school stuff or followed a tutorial, but never built something on your own.",
  },
  {
    value: "some",
    title: "A project or two",
    description:
      "You've shipped something on your own :) We'll show you cool new stuff to try next.",
  },
  {
    value: "experienced",
    title: "Always building",
    description:
      "You're constantly making things. We'll connect you to deeper resources and harder challenges.",
  },
];

export default class extends Controller {
  static targets = ["slider", "hidden", "title", "description", "submit"];

  connect() {
    this.render();
    this._setSubmitEnabled(false);
  }

  // Triggered by user input on the slider (drag, click, arrow keys).
  touch() {
    this.render();
    this._setSubmitEnabled(true);
  }

  render() {
    const idx = parseInt(this.sliderTarget.value, 10) || 0;
    const step = LEVELS[idx] || LEVELS[0];
    this.hiddenTarget.value = step.value;
    this.titleTarget.textContent = step.title;
    this.descriptionTarget.textContent = step.description;

    const ratio = idx / (LEVELS.length - 1);
    // Set on the form so the rail's fill div (a sibling of the input) can
    // inherit the variable.
    this.element.style.setProperty("--slider-fill", ratio);
  }

  _setSubmitEnabled(enabled) {
    if (!this.hasSubmitTarget) return;
    this.submitTarget.disabled = !enabled;
    this.submitTarget.classList.toggle("action-btn--disabled", !enabled);
  }
}
