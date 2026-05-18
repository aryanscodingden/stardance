import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["otherWrap", "otherInput"];

  connect() {
    const dialog = this.element.closest("dialog");
    if (dialog && !dialog.open) {
      dialog.showModal();
      document.body.style.overflow = "hidden";
    }
  }

  toggleOther(event) {
    const isOther = event.target.value === "Other";
    this.otherWrapTarget.hidden = !isOther;
    if (isOther) this.otherInputTarget.focus();
  }

  skip() {
    const dialog = this.element.closest("dialog");
    if (!dialog) return;
    if (dialog.classList.contains("user-ref-modal--closing")) return;

    dialog.classList.add("user-ref-modal--closing");

    const cleanup = () => {
      dialog.removeEventListener("transitionend", onTransitionEnd);
      clearTimeout(fallback);
      dialog.close();
      dialog.classList.remove("user-ref-modal--closing");
      document.body.style.overflow = "";
    };
    const onTransitionEnd = (event) => {
      if (event.target !== dialog || event.propertyName !== "opacity") return;
      cleanup();
    };
    dialog.addEventListener("transitionend", onTransitionEnd);
    const fallback = setTimeout(cleanup, 400);
  }
}
