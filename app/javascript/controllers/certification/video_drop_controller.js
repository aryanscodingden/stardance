import { Controller } from "@hotwired/stimulus";

// Drag-and-drop wrapper around the verdict video input. Drop or pick a file and
// it plays back a preview right away, so the reviewer can see it landed. Client
// checks mirror the server rules (Certification::Ship), so a file the model
// would reject gets caught here with a message instead of a silent failure.
const ACCEPTED = ["video/mp4", "video/webm", "video/quicktime"];
const MAX_BYTES = 250 * 1024 * 1024;

export default class extends Controller {
  static targets = ["input", "prompt", "preview", "video", "filename", "status"];
  static classes = ["over", "accepted", "error"];

  open() {
    this.inputTarget.click();
  }

  over(event) {
    event.preventDefault();
    this.element.classList.add(this.overClass);
  }

  leave(event) {
    event.preventDefault();
    this.element.classList.remove(this.overClass);
  }

  drop(event) {
    event.preventDefault();
    this.element.classList.remove(this.overClass);

    const file = event.dataTransfer.files?.[0];
    if (!file) return;

    const data = new DataTransfer();
    data.items.add(file);
    this.inputTarget.files = data.files;
    this.accept(file);
  }

  change() {
    const file = this.inputTarget.files?.[0];
    if (file) this.accept(file);
  }

  accept(file) {
    const problem = this.validate(file);
    if (problem) return this.reject(problem);

    this.revoke();
    this.objectUrl = URL.createObjectURL(file);
    this.videoTarget.src = this.objectUrl;
    this.filenameTarget.textContent = file.name;
    this.statusTarget.textContent = `Ready to upload (${this.mb(file.size)})`;

    this.element.classList.remove(this.errorClass);
    this.element.classList.add(this.acceptedClass);
    this.promptTarget.hidden = true;
    this.previewTarget.hidden = false;
  }

  reject(message) {
    this.inputTarget.value = "";
    this.revoke();
    this.element.classList.remove(this.acceptedClass);
    this.element.classList.add(this.errorClass);
    this.previewTarget.hidden = true;
    this.promptTarget.hidden = false;
    this.statusTarget.textContent = message;
  }

  validate(file) {
    if (!ACCEPTED.includes(file.type)) {
      return "That's not a supported video. Use mp4, webm, or mov.";
    }
    if (file.size > MAX_BYTES) {
      return `That video is ${this.mb(file.size)}. The max is 250 MB.`;
    }
    return null;
  }

  mb(bytes) {
    return `${(bytes / 1024 / 1024).toFixed(0)} MB`;
  }

  revoke() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl);
    this.objectUrl = null;
  }

  disconnect() {
    this.revoke();
  }
}
