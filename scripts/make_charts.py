"""Regenerates the charts in docs/images from the result files in this repo.

    pip install matplotlib && python scripts/make_charts.py
"""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "images"
NAVY, ORANGE, GREY, LIGHT = "#1F3864", "#ED7100", "#545B64", "#D5DBDB"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 12, "axes.edgecolor": LIGHT,
                     "axes.labelcolor": GREY, "xtick.color": GREY, "ytick.color": GREY})


def power_tuning():
    data = json.loads((ROOT / "power-tuning" / "results.json").read_text())["results"]
    mem = [r["memoryMB"] for r in data]
    dur = [r["avgDurationMs"] for r in data]
    cost = [r["estimatedCostPerInvocationUSD"] * 1e6 for r in data]
    labels = [f"{m} MB" for m in mem]

    fig, ax1 = plt.subplots(figsize=(12, 6.3), dpi=150)
    bars = ax1.bar(labels, dur, color=[LIGHT] * (len(mem) - 1) + [NAVY], width=0.55)
    for b, d in zip(bars, dur):
        ax1.text(b.get_x() + b.get_width() / 2, b.get_height() + 40, f"{d:,.0f} ms", ha="center", color=NAVY, fontweight="bold")
    ax1.set_ylabel("Average duration (ms)")
    ax1.set_ylim(0, max(dur) * 1.18)
    ax1.spines[["top", "right"]].set_visible(False)

    ax2 = ax1.twinx()
    ax2.plot(labels, cost, color=ORANGE, marker="o", linewidth=3, markersize=9)
    for x, c in zip(labels, cost):
        ax2.annotate(f"${c:.2f}", (x, c), textcoords="offset points", xytext=(0, 12), ha="center", color=ORANGE, fontweight="bold")
    ax2.set_ylabel("Cost per 1M invocations (USD, compute only)", color=ORANGE)
    ax2.set_ylim(0, max(cost) * 1.3)
    ax2.spines[["top"]].set_visible(False)

    fig.suptitle("Lambda Power Tuning: 1024 MB was the fastest and the cheapest", x=0.06, ha="left", fontsize=18, fontweight="bold", color=NAVY)
    ax1.set_title("Bars: average duration.  Line: compute cost per 1M invocations.", loc="left", color=GREY, fontsize=12, pad=12)
    fig.tight_layout()
    fig.savefig(OUT / "power-tuning-results.png", facecolor="white")


def load_test():
    runs = [json.loads(p.read_text()) for p in sorted((ROOT / "load-testing" / "results").glob("summary-*.json"))]
    runs.sort(key=lambda r: r["lambdaMemoryMB"])
    metrics = [("avgResponseMs", "Average"), ("p90Ms", "P90"), ("p95Ms", "P95"), ("p99Ms", "P99")]
    fig, ax = plt.subplots(figsize=(12, 6.3), dpi=150)
    width = 0.36
    colors = [LIGHT, NAVY]
    for i, run in enumerate(runs):
        xs = [j + (i - 0.5) * width for j in range(len(metrics))]
        vals = [run[k] for k, _ in metrics]
        bars = ax.bar(xs, vals, width, color=colors[i % 2], label=f'{run["lambdaMemoryMB"]} MB  ({run["totalRequests"]:,} requests, {run["errorPercent"]:.0f}% errors)')
        for b, v in zip(bars, vals):
            ax.text(b.get_x() + b.get_width() / 2, v + 12, f"{v:,.0f}", ha="center", color=NAVY if i else GREY, fontweight="bold")
    ax.set_xticks(range(len(metrics)), [m for _, m in metrics])
    ax.set_ylabel("Response time (ms)")
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(frameon=False, loc="upper left")
    fig.suptitle("Postman load test: 10 virtual users, 2 minutes, same request", x=0.06, ha="left", fontsize=18, fontweight="bold", color=NAVY)
    ax.set_title("Response time measured from the client, including the network round trip.", loc="left", color=GREY, fontsize=12, pad=12)
    fig.tight_layout()
    fig.savefig(OUT / "load-test-results.png", facecolor="white")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    power_tuning()
    load_test()
    print("charts written to", OUT)
