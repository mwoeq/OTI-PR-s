"""Сводит сырые замеры бенчмарка (results/benchmark*.csv, results/benchmark_q3*.csv)
в одну таблицу медиан и строит график results/benchmark.png.

Запуск: python scripts/08_summarize.py
"""
import glob
import statistics as st
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "results"
MB = 1024 * 1024


def read_csv(path):
    lines = Path(path).read_text(encoding="utf-8").strip().splitlines()
    head = lines[0].split(",")
    return [dict(zip(head, ln.split(","))) for ln in lines[1:] if ln]


# --- запись и размер: по каждому прогону суммируем 3 таблицы ---
size = defaultdict(list)       # cfg -> [МБ на прогон]
lineitem_mb = defaultdict(list)
write = defaultdict(list)      # cfg -> [секунд на запись всех 3 таблиц]
for f in sorted(glob.glob(str(RES / "benchmark.csv")) + glob.glob(str(RES / "benchmark_rep*.csv"))):
    per_run = defaultdict(lambda: [0, 0])
    for r in read_csv(f):
        cfg = f"{r['format']} {r['codec']}"
        per_run[cfg][0] += int(r["bytes"])
        per_run[cfg][1] += int(r["write_exec_ms"])
        if r["table"] == "lineitem":
            lineitem_mb[cfg].append(int(r["bytes"]) / MB)
    for cfg, (b, ms) in per_run.items():
        size[cfg].append(b / MB)
        write[cfg].append(ms / 1000)

# --- Q3: cold и медиана тёплых прогонов ---
cold = defaultdict(list)
warm = defaultdict(list)
for f in sorted(glob.glob(str(RES / "benchmark_q3*.csv"))):
    for r in read_csv(f):
        cfg = f"{r['format']} {r['codec']}"
        (cold if r["run"] == "cold" else warm)[cfg].append(int(r["exec_ms"]) / 1000)

order = ["PARQUET NONE", "PARQUET SNAPPY", "PARQUET GZIP", "PARQUET ZSTD", "ORC GZIP", "ORC ZSTD"]
order = [c for c in order if c in size]
base = st.median(size["PARQUET NONE"])

rows = []
for c in order:
    rows.append({
        "cfg": c,
        "n": len(size[c]),
        "size_mb": st.median(size[c]),
        "lineitem_mb": st.median(lineitem_mb[c]),
        "ratio": base / st.median(size[c]),
        "write_s": st.median(write[c]),
        "write_min": min(write[c]), "write_max": max(write[c]),
        "cold_s": st.median(cold[c]),
        "cold_min": min(cold[c]), "cold_max": max(cold[c]),
        "warm_s": st.median(warm[c]),
    })

md = ["| Конфигурация | Прогонов | Bronze, МБ | из них lineitem, МБ | Сжатие vs NONE | Запись, с (медиана; мин–макс) | Q3 cold, с (медиана; мин–макс) | Q3 warm, с (медиана) |",
      "|---|---|---|---|---|---|---|---|"]
for r in rows:
    md.append(f"| {r['cfg']} | {r['n']} | {r['size_mb']:.0f} | {r['lineitem_mb']:.0f} | ×{r['ratio']:.2f} | "
              f"{r['write_s']:.1f} ({r['write_min']:.1f}–{r['write_max']:.1f}) | "
              f"{r['cold_s']:.2f} ({r['cold_min']:.2f}–{r['cold_max']:.2f}) | {r['warm_s']:.2f} |")
(RES / "summary.md").write_text("\n".join(md) + "\n", encoding="utf-8")
print("\n".join(md))

# --- график: три панели с общей категориальной осью, у каждой своя шкала (без двойных осей) ---
SERIES = "#2a78d6"      # одна серия -> один цвет; подписи несут значения
TEXT, MUTED, GRID = "#1f1f1e", "#6b6a63", "#e1e0d9"
panels = [("size_mb", "Размер Bronze, МБ", "{:.0f}"),
          ("write_s", "Запись Bronze, с (медиана)", "{:.0f}"),
          ("cold_s", "Q3 холодный, с (медиана)", "{:.1f}")]
fig, axes = plt.subplots(1, 3, figsize=(13, 3.8), sharey=True)
labels = [r["cfg"] for r in rows]
y = range(len(rows))
for ax, (key, title, fmt) in zip(axes, panels):
    vals = [r[key] for r in rows]
    ax.barh(list(y), vals, height=0.6, color=SERIES)
    for yi, v in zip(y, vals):
        ax.text(v + max(vals) * 0.02, yi, fmt.format(v), va="center", fontsize=9, color=TEXT)
    ax.set_title(title, loc="left", fontsize=11, color=TEXT)
    ax.set_xlim(0, max(vals) * 1.2)
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=MUTED, labelsize=9, length=0)
axes[0].set_yticks(list(y))
axes[0].set_yticklabels(labels, color=TEXT)
axes[0].invert_yaxis()
fig.suptitle("Bronze (TPC-H sf10: customer + orders + lineitem) — формат × кодек", x=0.01, ha="left", fontsize=13, color=TEXT)
fig.tight_layout()
fig.savefig(RES / "benchmark.png", dpi=150)
print("saved", RES / "benchmark.png")
