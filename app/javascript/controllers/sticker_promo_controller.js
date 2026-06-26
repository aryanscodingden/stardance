import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog"];

  connect() {
    this.dialogTarget.showModal();
    document.body.style.overflow = "hidden";
  }

  dismiss() {
    const token = document.querySelector("meta[name='csrf-token']")?.content;
    fetch("/my/dismissals", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token || "",
      },
      body: JSON.stringify({ thing_name: "sticker_promo" }),
    }).catch(() => {});

    this.dialogTarget.close();
    document.body.style.overflow = "";
    this.element.remove();
  }
}
