import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["reason", "prevBtn", "nextBtn", "counter"];

  connect() {
    this.index = 0;
    this.update();
  }

  next() {
    if (this.index < this.reasonTargets.length - 1) {
      this.index++;
      this.update();
    }
  }

  prev() {
    if (this.index > 0) {
      this.index--;
      this.update();
    }
  }

  update() {
    const total = this.reasonTargets.length;

    this.reasonTargets.forEach((el, i) => {
      el.hidden = i !== this.index;
    });

    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${this.index + 1} / ${total}`;
    }

    if (this.hasPrevBtnTarget) {
      this.prevBtnTarget.disabled = this.index === 0;
    }

    if (this.hasNextBtnTarget) {
      this.nextBtnTarget.disabled = this.index === total - 1;
    }
  }
}
