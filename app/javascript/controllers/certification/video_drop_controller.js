import { Controller } from "@hotwired/stimulus";
import { DirectUpload } from "@rails/activestorage";

// Drag-and-drop video input with immediate Active Storage direct-upload.
// On file pick/drop the video is sent to storage straight away (not on form
// submit) also a progress bar tracks the
// transfer; and the submit button is locked/waiting until the upload finishes :)
const ACCEPTED = ["video/mp4", "video/webm", "video/quicktime"];
const MAX_BYTES = 250 * 1024 * 1024;

export default class extends Controller {
  static targets = [
    "input",
    "prompt",
    "preview",
    "video",
    "filename",
    "status",
    "progressWrapper",
    "progressBar",
    "submitBtn",
  ];
  static classes = ["over", "accepted", "uploading", "done", "error"];
  static values = { directUploadUrl: String };

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

    this.element.classList.remove(this.errorClass, this.doneClass, this.acceptedClass);
    this.promptTarget.hidden = true;
    this.previewTarget.hidden = false;

    this.startUpload(file);
  }

  startUpload(file) {
    this.setUploading(true);
    this.setProgress(0);
    this.statusTarget.textContent = `Uploading… 0 %`;

    const upload = new DirectUpload(file, this.directUploadUrlValue, this);
    upload.create((error, blob) => {
      if (error) {
        this.reject(`Upload failed: ${error}`);
        return;
      }

      this.inputTarget.value = "";
      const hiddenField = document.createElement("input");
      hiddenField.type = "hidden";
      hiddenField.name = this.inputTarget.name;
      hiddenField.value = blob.signed_id;
      this.element.appendChild(hiddenField);
      this.blobField = hiddenField;

      this.setUploading(false);
      this.element.classList.add(this.doneClass);
      this.statusTarget.textContent = `✓ Uploaded — ${this.mb(file.size)}`;
    });
  }

  directUploadWillStoreFileWithXHR(xhr) {
    xhr.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable) {
        const pct = Math.round((event.loaded / event.total) * 100);
        this.setProgress(pct);
        this.statusTarget.textContent = `Uploading… ${pct} %`;
      }
    });
  }

  reject(message) {
    this.inputTarget.value = "";
    this.revoke();
    this.blobField?.remove();
    this.blobField = null;
    this.element.classList.remove(this.acceptedClass, this.uploadingClass, this.doneClass);
    this.element.classList.add(this.errorClass);
    this.previewTarget.hidden = true;
    this.promptTarget.hidden = false;
    this.progressWrapperTarget.hidden = true;
    this.statusTarget.textContent = message;
    this.setUploading(false);
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

  setProgress(pct) {
    this.progressWrapperTarget.hidden = false;
    this.progressBarTarget.style.width = `${pct}%`;
    this.progressBarTarget.setAttribute("aria-valuenow", pct);
  }

  setUploading(uploading) {
    if (uploading) {
      this.element.classList.add(this.uploadingClass);
    } else {
      this.element.classList.remove(this.uploadingClass);
      this.progressWrapperTarget.hidden = true;
    }

    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = uploading;
    }
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
