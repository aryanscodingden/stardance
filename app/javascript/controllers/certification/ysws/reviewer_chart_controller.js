import { Controller } from "@hotwired/stimulus";
import Chart from "chart.js/auto";

// Brand palette (docs/branding.md). Cycled when there are more reviewers than
// colors, since the chart plots a line for every reviewer.
const PALETTE = [
  "#81FFFF", // mint
  "#EBB7FF", // lilac
  "#95DBFF", // blue
  "#FF8D9D", // salmon
  "#FFE564", // yellow
  "#FFD598", // peach
];

export default class extends Controller {
  static targets = ["canvas"];
  static values = {
    chart: Object, // { labels: [...], series: [{ name, data: [...] }] }
  };

  connect() {
    const { labels = [], series = [] } = this.chartValue || {};
    if (!series.length) return;

    const datasets = series.map((s, i) => {
      const color = PALETTE[i % PALETTE.length];
      return {
        label: s.name || "Unknown",
        data: s.data,
        borderColor: color,
        backgroundColor: color,
        tension: 0.3,
        pointRadius: 2,
      };
    });

    this.chart = new Chart(this.canvasTarget, {
      type: "line",
      data: { labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        scales: {
          x: {
            grid: { color: "rgba(255, 255, 255, 0.1)" },
            ticks: { color: "rgba(255, 255, 255, 0.7)" },
          },
          y: {
            beginAtZero: true,
            ticks: { color: "rgba(255, 255, 255, 0.7)", precision: 0 },
            grid: { color: "rgba(255, 255, 255, 0.1)" },
          },
        },
        plugins: {
          legend: { labels: { color: "rgba(255, 255, 255, 0.7)" } },
        },
      },
    });
  }

  disconnect() {
    this.chart?.destroy();
  }
}
