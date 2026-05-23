import { Controller } from "@hotwired/stimulus";

// Synthetic progress duration — a real upload would drive `#setProgress`
// from XHR/fetch progress events instead.
const FAKE_LOAD_DURATION_MS = 900;

const IDLE_PRIMARY = "Drag an image";
const IDLE_SECONDARY = "or click to choose a file";

export default class extends Controller {
  static targets = [
    "input",
    "placeholder",
    "preview",
    "progress",
    "progressBar",
    "primary",
    "secondary",
  ];

  connect() {
    // If the server pre-rendered the component with an existing image (e.g.
    // a project banner already attached), keep the "loaded" state and the
    // SSR'd primary/secondary text instead of clobbering them to idle.
    if (this.#state !== "loaded") {
      this.#setState("idle");
      this.#setText(IDLE_PRIMARY, IDLE_SECONDARY);
    }
  }

  disconnect() {
    this.#cancelLoad();
  }

  open(event) {
    if (event?.target === this.inputTarget) return;
    event?.preventDefault?.();
    if (this.#state === "loading") return;
    this.inputTarget.click();
  }

  dragEnter(event) {
    event.preventDefault();
    this.#dragDepth += 1;
    if (this.#state === "loading") return;
    this.#setState("dragging");
    this.#setText("Drop your image here…", "");
  }

  dragOver(event) {
    event.preventDefault();
  }

  dragLeave(event) {
    event.preventDefault();
    this.#dragDepth = Math.max(0, this.#dragDepth - 1);
    if (this.#dragDepth === 0 && this.#state === "dragging") {
      this.#setState("idle");
      this.#setText(IDLE_PRIMARY, IDLE_SECONDARY);
    }
  }

  drop(event) {
    event.preventDefault();
    this.#dragDepth = 0;
    const file = event.dataTransfer?.files?.[0];
    if (file) this.#beginLoad(file);
  }

  fileSelected(event) {
    const file = event.target.files?.[0];
    if (file) this.#beginLoad(file);
  }

  reset(event) {
    event?.preventDefault?.();
    event?.stopPropagation?.();
    this.#cancelLoad();
    this.inputTarget.value = "";
    this.previewTarget.innerHTML = "";
    this.previewTarget.hidden = true;
    this.placeholderTarget.hidden = false;
    this.#setProgress(0);
    this.#setState("idle");
    this.#setText(IDLE_PRIMARY, IDLE_SECONDARY);
  }

  #beginLoad(file) {
    this.#cancelLoad();
    const loadId = ++this.#loadId;

    if (!file.type.startsWith("image/")) {
      this.#setState("error");
      this.#setText("That's not an image", file.name);
      return;
    }

    this.#setState("loading");
    this.#setText("Loading…", file.name);
    this.#setProgress(0);

    const start = performance.now();
    const tick = () => {
      if (loadId !== this.#loadId) return;
      const pct = Math.min(
        99,
        ((performance.now() - start) / FAKE_LOAD_DURATION_MS) * 100,
      );
      this.#setProgress(pct);
      if (this.#state === "loading") this.#rafId = requestAnimationFrame(tick);
    };
    this.#rafId = requestAnimationFrame(tick);

    const reader = new FileReader();
    this.#reader = reader;
    reader.onload = () => {
      if (loadId !== this.#loadId) return;
      const url = reader.result;
      const elapsed = performance.now() - start;
      const remaining = Math.max(0, FAKE_LOAD_DURATION_MS - elapsed);
      this.#timeoutId = setTimeout(() => {
        if (loadId !== this.#loadId) return;
        this.placeholderTarget.hidden = true;
        this.previewTarget.innerHTML = `<img src="${url}" alt="${file.name}" class="star-image-input__image">`;
        this.previewTarget.hidden = false;
        this.#setProgress(100);
        this.#setState("loaded");
        this.#setText(file.name, "Click to replace");
      }, remaining);
    };
    reader.onerror = () => {
      if (loadId !== this.#loadId) return;
      this.#setState("error");
      this.#setText("Couldn't read file", file.name);
    };
    reader.readAsDataURL(file);
  }

  #cancelLoad() {
    this.#loadId += 1;
    if (this.#rafId != null) {
      cancelAnimationFrame(this.#rafId);
      this.#rafId = null;
    }
    if (this.#timeoutId != null) {
      clearTimeout(this.#timeoutId);
      this.#timeoutId = null;
    }
    if (this.#reader && this.#reader.readyState === FileReader.LOADING) {
      this.#reader.abort();
    }
    this.#reader = null;
  }

  get #state() {
    return this.element.dataset.state;
  }

  #setState(state) {
    this.element.dataset.state = state;
  }

  #setText(primary, secondary) {
    if (this.hasPrimaryTarget) this.primaryTarget.textContent = primary;
    if (this.hasSecondaryTarget) this.secondaryTarget.textContent = secondary;
  }

  #setProgress(pct) {
    const v = Math.max(0, Math.min(100, pct));
    if (Math.abs(v - this.#lastProgress) < 0.5 && v !== 100) return;
    this.#lastProgress = v;
    if (this.hasProgressBarTarget) this.progressBarTarget.style.width = `${v}%`;
  }

  #dragDepth = 0;
  #loadId = 0;
  #rafId = null;
  #timeoutId = null;
  #reader = null;
  #lastProgress = -1;
}
