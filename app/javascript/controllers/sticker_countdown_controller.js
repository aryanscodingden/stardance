import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { deadline: String };
  static targets = ["timer"];

  connect() {
    this.render();
    this.interval = setInterval(() => this.render(), 1000);
  }

  disconnect() {
    clearInterval(this.interval);
  }

  render() {
    const remaining = new Date(this.deadlineValue).getTime() - Date.now();
    const secs = Math.max(0, Math.floor(remaining / 1000));
    const days = Math.floor(secs / 86400);
    const hours = Math.floor((secs % 86400) / 3600);
    const mins = Math.floor((secs % 3600) / 60);
    const s = secs % 60;

    const pad = (n) => String(n).padStart(2, "0");
    let text;
    if (days > 0) {
      text = `${days}d ${hours}h ${mins}m ${pad(s)}s`;
    } else if (hours > 0) {
      text = `${hours}h ${mins}m ${pad(s)}s`;
    } else {
      text = `${mins}m ${pad(s)}s`;
    }

    this.timerTarget.textContent = text;
  }
}
