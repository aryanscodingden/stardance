import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["form", "textarea", "submitButton"];
  static values = { shipId: Number };

  toggle(event) {
    event.preventDefault();
    const opening = this.formTarget.hidden;
    this.formTarget.hidden = !opening;
    if (opening) this.textareaTarget.focus();
    else this.textareaTarget.value = "";
  }

  async submit(event) {
    event.preventDefault();
    const details = this.textareaTarget.value.trim();

    if (details.length < 20) {
      alert("Please provide at least 20 characters describing the issue.");
      return;
    }

    this.submitButtonTarget.disabled = true;
    this.submitButtonTarget.textContent = "Sending...";

    try {
      const csrfToken = document.querySelector(
        'meta[name="csrf-token"]',
      ).content;
      const response = await fetch(
        `/admin/certification/ship/${this.shipIdValue}/report_fraud`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
          },
          body: JSON.stringify({ details }),
        },
      );

      const data = await response.json();

      if (response.ok) {
        alert("Reported. The fraud squad has been notified.");
        this.formTarget.hidden = true;
        this.textareaTarget.value = "";
      } else {
        const errorMessage = data.errors
          ? data.errors.join(", ")
          : "Failed to submit report";
        alert(`Error: ${errorMessage}`);
      }
    } catch (error) {
      console.error("Error submitting fraud report:", error);
      alert("An unexpected error occurred. Please try again.");
    } finally {
      this.submitButtonTarget.disabled = false;
      this.submitButtonTarget.textContent = "Send report";
    }
  }
}
