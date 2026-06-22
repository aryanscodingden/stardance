import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog", "textarea", "body", "repliesFrame"];

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

  open() {
    this._scrollY = window.scrollY;
    this._previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    this.dialogTarget.showModal();

    // Keep the thread scrolled to the original post on open, and focus the
    // composer without yanking the scroll position down to it.
    if (this.hasBodyTarget) {
      this.bodyTarget.scrollTop = 0;
    }
    if (this.hasTextareaTarget) {
      requestAnimationFrame(() =>
        this.textareaTarget.focus({ preventScroll: true }),
      );
    }
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

    // Keep the modal open and refresh the thread so the new reply lands in
    // context; repliesLoaded then scrolls it into view.
    if (this.hasRepliesFrameTarget) {
      this._scrollToEndOnLoad = true;
      this.repliesFrameTarget.reload();
    }
  }

  repliesLoaded() {
    if (!this._scrollToEndOnLoad) return;
    this._scrollToEndOnLoad = false;

    if (this.hasBodyTarget) {
      this.bodyTarget.scrollTo({
        top: this.bodyTarget.scrollHeight,
        behavior: "smooth",
      });
    }
  }
}
