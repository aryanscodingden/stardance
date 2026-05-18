import { Controller } from "@hotwired/stimulus";

// Lazy-load the Vimeo Player SDK once per page. Returned promise resolves
// when window.Vimeo is available.
let sdkPromise = null;
function loadVimeoSdk() {
  if (window.Vimeo && window.Vimeo.Player) return Promise.resolve();
  if (sdkPromise) return sdkPromise;
  sdkPromise = new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "https://player.vimeo.com/api/player.js";
    s.async = true;
    s.onload = () => resolve();
    s.onerror = reject;
    document.head.appendChild(s);
  });
  return sdkPromise;
}

// Wraps a Vimeo iframe with custom play/pause, scrub, and mute controls.
// The video starts muted (browsers block unmuted autoplay without a user
// gesture). Until the user unmutes for the first time, a prominent prompt
// is shown in the top-right of the video and any click on the wrapper
// unmutes instead of toggling play/pause. Once that first unmute lands,
// the prompt is permanently removed and clicks revert to play/pause —
// re-muting via the controls does not bring the prompt back.
export default class extends Controller {
  static targets = ["iframe", "scrub"];

  async connect() {
    await loadVimeoSdk();
    if (!this.element.isConnected) return;

    this.player = new window.Vimeo.Player(this.iframeTarget);
    this.isScrubbing = false;

    // Show the big top-right unmute prompt and arm the click-to-unmute
    // behavior on wrapperClick. Cleared on first successful unmute below.
    this.element.classList.add("hero__video--needs-unmute");
    this.element.classList.add("hero__video--muted");

    this.player.ready().then(async () => {
      try {
        const duration = await this.player.getDuration();
        this.scrubTarget.max = String(duration);
      } catch (_) {}
      try {
        const muted = await this.player.getMuted();
        this._setMutedState(muted);
      } catch (_) {}
    });

    this.player.on("play", () => this._setPlayState(true));
    this.player.on("pause", () => this._setPlayState(false));
    this.player.on("timeupdate", ({ seconds, percent }) => {
      if (!this.isScrubbing) {
        this.scrubTarget.value = String(seconds);
        this._setProgress(percent);
      }
    });
    this.player.on("volumechange", async () => {
      const muted = await this.player.getMuted();
      this._setMutedState(muted);
      if (!muted) {
        this.element.classList.remove("hero__video--needs-unmute");
      }
    });
    this._onFullscreenChange = () => {
      this._setFullscreenState(document.fullscreenElement === this.element);
    };
    document.addEventListener("fullscreenchange", this._onFullscreenChange);

    this._setupPin();
  }

  disconnect() {
    if (this._onPinScroll) {
      window.removeEventListener("scroll", this._onPinScroll);
    }
    if (this._onFullscreenChange) {
      document.removeEventListener(
        "fullscreenchange",
        this._onFullscreenChange,
      );
    }
    if (this.player) this.player.destroy().catch(() => {});
  }

  // Pins the wrapper to the bottom-right of the viewport once the hero has
  // scrolled out of view. The same DOM element keeps playing — class flips
  // drive slide-in / slide-out animations.
  //
  // States: "unset" → "pinned" → "unpinning" → "unset".
  // "unpinning" keeps the .--pinned class (so the element stays fixed at the
  // bottom-right) while .--unpinning overrides the animation with the reverse;
  // both are stripped on animationend so the element returns to its hero spot.
  _setupPin() {
    this._hero = document.querySelector(".section.hero");
    if (!this._hero) return;
    this._pinState = "unset";
    this._pinTicking = false;
    this._onPinScroll = () => {
      if (this._pinTicking) return;
      this._pinTicking = true;
      requestAnimationFrame(() => {
        this._pinTicking = false;
        const bottom = this._hero.getBoundingClientRect().bottom;
        this._setPinned(bottom < 60);
      });
    };
    this._onPinAnimationEnd = (e) => {
      if (e.animationName !== "hero-video-pin-out") return;
      if (this._pinState !== "unpinning") return;
      this.element.classList.remove("hero__video--pinned");
      this.element.classList.remove("hero__video--unpinning");
      this._pinState = "unset";
    };
    window.addEventListener("scroll", this._onPinScroll, { passive: true });
    this.element.addEventListener("animationend", this._onPinAnimationEnd);
    this._onPinScroll();
  }

  _setPinned(wantPinned) {
    if (wantPinned) {
      if (this._pinState === "unpinning") {
        // Cancel the slide-out — element is still fixed, drop the override.
        this.element.classList.remove("hero__video--unpinning");
        this._pinState = "pinned";
      } else if (this._pinState === "unset") {
        this.element.classList.add("hero__video--pinned");
        this._pinState = "pinned";
      }
    } else if (this._pinState === "pinned") {
      // If the user dismissed the pinned mini-player, scrolling back up
      // resets it: drop the dismissed + pinned classes immediately so the
      // video reappears in its hero spot (skip the slide-out, since it's
      // already invisible in the corner).
      if (this.element.classList.contains("hero__video--dismissed")) {
        this.element.classList.remove("hero__video--pinned");
        this.element.classList.remove("hero__video--dismissed");
        this._pinState = "unset";
      } else {
        this.element.classList.add("hero__video--unpinning");
        this._pinState = "unpinning";
      }
    }
  }

  togglePlay(e) {
    if (e) e.preventDefault();
    this.player.getPaused().then((paused) => {
      if (paused) this.player.play();
      else this.player.pause();
    });
  }

  // Click anywhere on the video (outside the controls) — first click while
  // the unmute prompt is showing unmutes the video; subsequent clicks toggle
  // play/pause as usual.
  wrapperClick(e) {
    if (e.target.closest(".hero__video-controls")) return;
    if (e.target.closest(".hero__video-star")) return;
    if (!this.player) return;
    if (this.element.classList.contains("hero__video--needs-unmute")) {
      e.preventDefault();
      this._tryUnmute();
      return;
    }
    this.togglePlay(e);
  }

  // Star click: only meaningful when the video is pinned to the corner —
  // dismisses the pinned video for the rest of the session.
  starClick(e) {
    if (!this.element.classList.contains("hero__video--pinned")) return;
    e.preventDefault();
    e.stopPropagation();
    this.element.classList.add("hero__video--dismissed");
    if (this.player) this.player.pause().catch(() => {});
  }

  toggleMute(e) {
    e.preventDefault();
    this.player.getMuted().then((muted) => {
      if (muted) this._tryUnmute();
      else this.player.setMuted(true);
    });
  }

  toggleFullscreen(e) {
    e.preventDefault();
    e.stopPropagation();
    if (document.fullscreenElement === this.element) {
      document.exitFullscreen().catch(() => {});
    } else {
      this.element.requestFullscreen().catch(() => {});
    }
  }

  scrubInput() {
    this.isScrubbing = true;
    // Live-update the filled-progress visual as the user drags.
    const max = parseFloat(this.scrubTarget.max) || 0;
    const val = parseFloat(this.scrubTarget.value) || 0;
    this._setProgress(max > 0 ? val / max : 0);
  }

  scrubChange() {
    const t = parseFloat(this.scrubTarget.value);
    this.player
      .setCurrentTime(t)
      .catch(() => {})
      .finally(() => {
        this.isScrubbing = false;
      });
  }

  _setProgress(fraction) {
    const pct = Math.max(0, Math.min(1, fraction || 0)) * 100;
    this.scrubTarget.style.setProperty("--progress", `${pct.toFixed(2)}%`);
  }

  async _tryUnmute() {
    try {
      await this.player.setMuted(false);
      await this.player.setVolume(0.7);
    } catch (_) {
      // Autoplay policy blocked us — stay muted until a user gesture.
    }
  }

  _setPlayState(playing) {
    this.element.classList.toggle("hero__video--playing", playing);
  }

  _setMutedState(muted) {
    this.element.classList.toggle("hero__video--muted", muted);
  }

  _setFullscreenState(fullscreen) {
    this.element.classList.toggle("hero__video--fullscreen", fullscreen);
  }
}
