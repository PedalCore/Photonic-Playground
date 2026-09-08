"""Plot measured native Godot benchmarks; no simulations or fitted scores here."""
import json
from io import BytesIO
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parent / "results"
order = json.loads((ROOT / "pulse-order.json").read_text())
xor = json.loads((ROOT / "pulse-xor.json").read_text())
names = list(order["runs"][0]["results"])
# JSON preserves the benchmark's display order, but make it explicit for Godot
# builds that serialize dictionary keys in a different order.
names = ["Input count", "Full timing (linear)", "Timing + products", "Leaky state",
         "LIF spike timing", "Passive: final power", "Passive: power history",
         "Passive: spike history", "Feedback: power history", "Feedback: spike history"]
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11,
                     "axes.spines.top": False, "axes.spines.right": False,
                     "axes.spines.left": False})
fig, axes = plt.subplots(1, 2, figsize=(12.8, 6.5), sharey=True)
fig.patch.set_facecolor("#f5f7f8")
for ax, data, title, color in zip(axes, [order, xor],
                                 ["Recover interval order", "Timing XOR: same or different?"],
                                 ["#197f76", "#5368b0"]):
    values = np.array([[run["results"][name]["test_accuracy"] * 100
                        for name in names] for run in data["runs"]])
    means = values.mean(axis=0)
    y = np.arange(len(names))
    ax.set_facecolor("#f5f7f8")
    ax.barh(y, means, height=.55, color=color, alpha=.85, zorder=2)
    for seed_index in range(len(values)):
        ax.scatter(values[seed_index], y + (seed_index - 1) * .105,
                   s=12, color="#101e2b", zorder=3)
    for index, mean in enumerate(means):
        ax.text(107, index, f"{mean:.1f}", va="center", ha="center", fontsize=10)
    ax.axvline(50, color="#8e979f", ls="--", lw=1, zorder=1)
    ax.set_xlim(0, 113)
    ax.set_xticks([0, 25, 50, 75, 100])
    ax.set_yticks(y, names)
    ax.tick_params(axis="y", length=0)
    ax.set_xlabel("Held-out accuracy (%)")
    ax.set_title(title, loc="left", fontsize=14, fontweight="bold", pad=14)
    ax.grid(axis="x", color="#dce2e6", lw=.7, zorder=0)
axes[0].invert_yaxis()
fig.suptitle("Wave memory is useful. These defaults do not beat the digital control.",
             x=.025, ha="left", fontsize=17, fontweight="bold", y=.98)
fig.text(.025, .91, "Three fixed seeds · 160 test sequences per seed · ±20% interval jitter · Godot 4.4.1",
         color="#53616b", fontsize=11)
fig.text(.025, .035, "Bars: mean across seeds. Dots: each seed. Dashed line: chance.\n"
         "Reduced 8-mode cavity + 6 threshold nodes; ideal dynamics, no device-noise or hardware advantage claim.",
         fontsize=10, color="#53616b")
fig.subplots_adjust(left=.215, right=.98, bottom=.17, top=.82, wspace=.18)
buffer = BytesIO()
fig.savefig(buffer, format="png", dpi=170, facecolor=fig.get_facecolor())
(ROOT / "pulse-comparison.png").write_bytes(buffer.getvalue())
print(ROOT / "pulse-comparison.png")
