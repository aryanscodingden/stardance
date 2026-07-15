import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["tab", "panel", "filters", "countdown"];
  static values = { period: String };

  connect() {
    this.tick();
    this.timer = setInterval(() => this.tick(), 1000);
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer);
  }

  switch(event) {
    const period = event.currentTarget.dataset.period;
    this.periodValue = period;

    this.tabTargets.forEach((tab) =>
      tab.classList.toggle("is-active", tab.dataset.period === period),
    );
    this.panelTargets.forEach((panel) =>
      panel.classList.toggle("is-hidden", panel.dataset.period !== period),
    );
  }

  submit() {
    if (this.hasFiltersTarget) this.filtersTarget.requestSubmit();
  }

  tick() {
    const now = Date.now();
    this.countdownTargets.forEach((el) => {
      const target = new Date(el.dataset.expiresAt).getTime();
      const remaining = Math.max(0, Math.floor((target - now) / 1000));
      if (remaining <= 0) {
        el.textContent = "expired";
        el.classList.add("is-expired");
        return;
      }
      const m = Math.floor(remaining / 60);
      const s = remaining % 60;
      el.textContent = `${m}:${s.toString().padStart(2, "0")} left`;
    });
  }
}
