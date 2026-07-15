import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog", "textarea", "body", "contentFrame"];
  static values = { contentUrl: String };

  connect() {
    this._scrollToEndOnLoad = false;
    this._previousOverflow = "";
    this._scrollY = 0;
    this._onClose = () => this._restoreScroll();
    this.dialogTarget.addEventListener("close", this._onClose);
  }

  disconnect() {
    this.dialogTarget.removeEventListener("close", this._onClose);
  }

  open(event) {
    // The trigger is a real link to the devlog's comments; let modified clicks
    // (open in new tab/window) fall through to the browser's default.
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
      return;

    event.preventDefault();

    this._scrollY = window.scrollY;
    this._previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    this.dialogTarget.showModal();

    if (this.hasContentFrameTarget && !this.contentFrameTarget.src) {
      this.contentFrameTarget.src = this.contentUrlValue;
    }

    this.focusComposer();
  }

  close() {
    this.dialogTarget.close();
  }

  _restoreScroll() {
    document.body.style.overflow = this._previousOverflow;
    window.scrollTo(0, this._scrollY);
  }

  backdropClick(event) {
    if (event.target !== this.dialogTarget) return;

    const rect = this.dialogTarget.getBoundingClientRect();
    const inside =
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom;

    if (!inside) this.close();
  }

  formSubmitted(event) {
    if (!event.detail.success) return;

    if (this.hasTextareaTarget) {
      this.textareaTarget.value = "";
    }

    if (this.hasContentFrameTarget) {
      this._scrollToEndOnLoad = true;
      this.contentFrameTarget.reload();
    }
  }

  contentLoaded() {
    if (!this._scrollToEndOnLoad) {
      if (this.hasBodyTarget) this.bodyTarget.scrollTop = 0;
      this.focusComposer();
      return;
    }

    this._scrollToEndOnLoad = false;
    if (this.hasBodyTarget) {
      this.bodyTarget.scrollTo({
        top: this.bodyTarget.scrollHeight,
        behavior: "smooth",
      });
    }
  }

  focusComposer() {
    if (!this.hasTextareaTarget) return;

    requestAnimationFrame(() =>
      this.textareaTarget.focus({ preventScroll: true }),
    );
  }
}
