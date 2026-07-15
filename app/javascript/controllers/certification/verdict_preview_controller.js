import { Controller } from "@hotwired/stimulus";

// Intercepts the review form submit to show a confirmation preview of the
// verdict + feedback before it's sent to the user. The modal shell, backdrop,
// esc, and scroll-lock are handled by the shared `modal` controller on the
// dialog itself, so this controller only builds the preview and re-submits.
export default class extends Controller {
  static targets = [
    "modal",
    "verdict",
    "feedbackBlock",
    "feedback",
    "noFeedback",
  ];

  intercept(event) {
    if (this._confirmed) {
      this._confirmed = false;
      return;
    }

    event.preventDefault();
    this.#buildPreview(event.target);
    if (this.hasModalTarget) this.modalTarget.showModal();
  }

  confirm() {
    this._confirmed = true;
    if (this.hasModalTarget) this.modalTarget.close();
    this.element.querySelector("form.review-form")?.requestSubmit();
  }

  #buildPreview(form) {
    const verdict =
      form.querySelector("input[name$='[status]']:checked")?.value ?? null;

    if (this.hasVerdictTarget) {
      const labels = { approved: "Approved", returned: "Rejected" };
      this.verdictTarget.textContent = verdict
        ? (labels[verdict] ?? verdict)
        : "—";
      this.verdictTarget.className =
        "status-pill" + (verdict ? ` status-pill--${verdict}` : "");
    }

    const text =
      form.querySelector("textarea[name$='[feedback]']")?.value.trim() ?? "";

    if (
      this.hasFeedbackTarget &&
      this.hasFeedbackBlockTarget &&
      this.hasNoFeedbackTarget
    ) {
      this.feedbackTarget.textContent = text;
      this.feedbackBlockTarget.hidden = !text;
      this.noFeedbackTarget.hidden = Boolean(text);
    }
  }
}
