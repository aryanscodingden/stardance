import { Controller } from "@hotwired/stimulus";

// Launches a Lookout screen-recording session from a hardware project page.
// Creates the session server-side, then opens Stardance's own recorder page
// (the Desktop / Browser / Camera chooser) in a new tab. The recorder page
// handles capture, the timelapse preview, and forwarding the time to Hackatime.
export default class extends Controller {
  static values = { createUrl: String };

  async record() {
    // Open the tab synchronously *inside* the click so the browser keeps it as a
    // user gesture — opening it after the `await` below trips popup blockers and
    // the recorder silently never appears.
    const recorderWindow = window.open("", "_blank");

    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken(),
        },
      });

      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        // Hardware projects moved to Outpost — show the notice instead of
        // recording. Prefer the popup already on the page; otherwise send the
        // just-opened tab to the project page, where it auto-opens.
        if (body.hardware_outpost_redirect) {
          const popup = document.getElementById("hardware-outpost-modal");
          if (popup) {
            recorderWindow?.close();
            popup.showModal();
          } else if (recorderWindow) {
            recorderWindow.location = body.hardware_outpost_redirect;
          } else {
            window.location.assign(body.hardware_outpost_redirect);
          }
          return;
        }
        throw new Error(body.error || `The server returned ${res.status}.`);
      }

      const session = await res.json();
      const recorderUrl = session.record_url;
      if (!recorderUrl) throw new Error("No recorder URL was returned.");

      if (recorderWindow) {
        recorderWindow.location = recorderUrl;
      } else {
        // The tab was blocked even synchronously — try once more as a fallback.
        window.open(recorderUrl, "_blank");
      }
    } catch (error) {
      if (recorderWindow) recorderWindow.close();
      console.error("Lookout record error", error);
      window.alert(`Couldn't start a screen recording.\n\n${error.message}`);
    }
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || "";
  }
}
