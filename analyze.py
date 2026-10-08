#!/usr/bin/env python3
"""
PBL-2 Task 7: AI-based design parameter analysis (delay, power, speed).

Reads sweep/results.csv produced by sweep.tcl and:
  1. derives speed/energy metrics (Fmax, program runtime, energy per instruction)
  2. trains ML models that predict Fmax, power and LUTs from the design knobs,
     scored with leave-one-out cross-validation (the dataset is small)
  3. fits a physics-informed power model  P = P_static + k * f
  4. uses the best models to predict the whole design space, including
     operating points that were never run, and recommends operating points
  5. writes plots + sweep/analysis_report.md for the PBL write-up

Usage:  python3 analyze.py [path/to/results.csv]
Deps:   pip install pandas numpy scikit-learn matplotlib tabulate
"""
import sys, json
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.linear_model import Ridge, LinearRegression
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.preprocessing import PolynomialFeatures, StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.model_selection import LeaveOneOut, cross_val_predict
from sklearn.inspection import permutation_importance

PROGRAM_CYCLES = 49          # cycles for the 36-instruction test program (CPI = 1)

csv = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("sweep/results.csv")
out = csv.parent
plots = out / "plots"
plots.mkdir(parents=True, exist_ok=True)

# ----------------------------------------------------------------- load
df = pd.read_csv(csv)
df = df[df["status"] != "failed"].copy()
num = ["period_ns", "wns_ns", "fmax_mhz", "logic_levels", "path_delay_ns",
       "logic_delay_ns", "net_delay_ns", "luts", "lutram", "ffs", "carry4",
       "total_power_w", "dynamic_power_w", "static_power_w"]
df[num] = df[num].apply(pd.to_numeric, errors="coerce")
df = df.replace(-1, np.nan)
if len(df) < 4:
    sys.exit(f"Only {len(df)} usable runs - need at least 4. Run the full sweep.")

# ----------------------------------------------------------------- derived metrics
df["target_mhz"]       = 1000.0 / df["period_ns"]
df["meets_timing"]     = df["wns_ns"] >= 0
df["runtime_ns"]       = PROGRAM_CYCLES * df["period_ns"]       # at target clock
df["energy_per_instr_nJ"] = df["total_power_w"] * df["period_ns"]  # W * ns = nJ, CPI=1
df["logic_frac"]       = df["logic_delay_ns"] / df["path_delay_ns"]

# ----------------------------------------------------------------- features
dirs = sorted(df["synth_directive"].unique())
def featurize(frame):
    X = pd.DataFrame({"freq_mhz": 1000.0 / frame["period_ns"]})
    for d in dirs:
        X[f"dir_{d}"] = (frame["synth_directive"] == d).astype(float)
    return X
X = featurize(df)

candidates = {
    "Ridge (poly-2)":    lambda: make_pipeline(PolynomialFeatures(2), StandardScaler(), Ridge(alpha=1.0)),
    "Random forest":     lambda: RandomForestRegressor(n_estimators=300, min_samples_leaf=1, random_state=0),
    "Gradient boosting": lambda: GradientBoostingRegressor(n_estimators=200, max_depth=2,
                                                           learning_rate=0.05, random_state=0),
}
targets = {"fmax_mhz": "Achieved Fmax (MHz)",
           "total_power_w": "Total power (W)",
           "luts": "Slice LUTs"}

loo = LeaveOneOut()
models, scores, loo_preds = {}, {}, {}
for t in targets:
    y = df[t].values
    ok = ~np.isnan(y)
    if ok.sum() < 4:
        continue
    best = None
    scores[t] = {}
    for name, make in candidates.items():
        pred = cross_val_predict(make(), X[ok], y[ok], cv=loo)
        mae = float(np.mean(np.abs(pred - y[ok])))
        mape = float(np.mean(np.abs(pred - y[ok]) / np.abs(y[ok]))) * 100
        scores[t][name] = {"MAE": mae, "MAPE_%": mape}
        if best is None or mae < best[1]:
            best = (name, mae, pred)
    models[t] = (best[0], candidates[best[0]]().fit(X[ok], y[ok]))
    loo_preds[t] = (y[ok], best[2])

# ----------------------------------------------------------------- feature importance
importance = {}
for t, (name, m) in models.items():
    ok = ~df[t].isna()
    r = permutation_importance(m, X[ok], df.loc[ok, t], n_repeats=30, random_state=0)
    importance[t] = dict(sorted(zip(X.columns, r.importances_mean), key=lambda kv: -kv[1]))

# ----------------------------------------------------------------- physics-informed power model
phys = {}
for d in dirs:
    sub = df[(df["synth_directive"] == d) & df["total_power_w"].notna()]
    if len(sub) >= 2:
        lr = LinearRegression().fit(sub[["target_mhz"]], sub["total_power_w"])
        r2 = lr.score(sub[["target_mhz"]], sub["total_power_w"])
        phys[d] = {"P_static_W": float(lr.intercept_),
                   "k_mW_per_MHz": float(lr.coef_[0] * 1000), "R2": float(r2)}

# ----------------------------------------------------------------- design-space prediction
grid_p = np.round(np.arange(6.0, 30.01, 0.5), 2)
grid = pd.DataFrame([(p, d) for d in dirs for p in grid_p],
                    columns=["period_ns", "synth_directive"])
Xg = featurize(grid)
for t, (name, m) in models.items():
    grid[f"pred_{t}"] = m.predict(Xg)
grid["target_mhz"] = 1000.0 / grid["period_ns"]

recs = {}
if "pred_fmax_mhz" in grid:
    # predicted to close timing if the model's Fmax >= target frequency
    grid["pred_meets"] = grid["pred_fmax_mhz"] >= grid["target_mhz"]
    for d in dirs:
        g = grid[(grid["synth_directive"] == d) & grid["pred_meets"]]
        if len(g):
            r = g.loc[g["target_mhz"].idxmax()]
            recs[d] = {"fastest_safe_period_ns": float(r["period_ns"]),
                       "freq_mhz": round(float(r["target_mhz"]), 2)}
            if "pred_total_power_w" in grid:
                recs[d]["pred_power_w"] = round(float(r["pred_total_power_w"]), 4)
                recs[d]["pred_energy_per_instr_nJ"] = round(
                    float(r["pred_total_power_w"] * r["period_ns"]), 3)

# ----------------------------------------------------------------- Pareto front (measured)
met = df[df["meets_timing"] & df["total_power_w"].notna()].sort_values("target_mhz", ascending=False)
pareto, best_p = [], np.inf
for _, r in met.iterrows():
    if r["total_power_w"] < best_p:
        pareto.append(r["run"]); best_p = r["total_power_w"]

# ----------------------------------------------------------------- plots
mk = dict(zip(dirs, ["o", "s", "^", "D", "v"]))

fig, ax = plt.subplots(figsize=(6.5, 4.5))
for d in dirs:
    s = df[df["synth_directive"] == d]
    ax.scatter(s["target_mhz"], s["fmax_mhz"], marker=mk[d], label=f"{d} (measured)")
    if "pred_fmax_mhz" in grid:
        g = grid[grid["synth_directive"] == d]
        ax.plot(g["target_mhz"], g["pred_fmax_mhz"], alpha=0.6)
lim = [0, max(df["target_mhz"].max(), df["fmax_mhz"].max()) * 1.1]
ax.plot(lim, lim, "k--", lw=0.8, label="Fmax = target")
ax.set_xlabel("Target clock (MHz)"); ax.set_ylabel("Achieved Fmax (MHz)")
ax.set_title("Speed: achieved vs target clock"); ax.legend(fontsize=7); ax.grid(alpha=0.3)
fig.tight_layout(); fig.savefig(plots / "fmax_vs_target.png", dpi=150); plt.close(fig)

fig, ax = plt.subplots(figsize=(6.5, 4.5))
for d in dirs:
    s = df[df["synth_directive"] == d]
    ax.scatter(s["target_mhz"], s["total_power_w"], marker=mk[d], label=d)
    if d in phys:
        f = np.linspace(0, df["target_mhz"].max() * 1.1, 50)
        ax.plot(f, phys[d]["P_static_W"] + phys[d]["k_mW_per_MHz"] / 1000 * f, alpha=0.6)
ax.set_xlabel("Clock frequency (MHz)"); ax.set_ylabel("Total on-chip power (W)")
ax.set_title("Power vs frequency (lines: P = P_static + k*f)"); ax.legend(fontsize=7); ax.grid(alpha=0.3)
fig.tight_layout(); fig.savefig(plots / "power_vs_freq.png", dpi=150); plt.close(fig)

fig, ax = plt.subplots(figsize=(6.5, 4.5))
ax.scatter(df["fmax_mhz"], df["total_power_w"], c="lightgray", label="all runs")
ax.scatter(met["fmax_mhz"], met["total_power_w"], label="meets timing")
pf = df[df["run"].isin(pareto)].sort_values("fmax_mhz")
ax.plot(pf["fmax_mhz"], pf["total_power_w"], "r-o", label="Pareto front")
ax.set_xlabel("Achieved Fmax (MHz)"); ax.set_ylabel("Total power (W)")
ax.set_title("Speed / power trade-off"); ax.legend(fontsize=7); ax.grid(alpha=0.3)
fig.tight_layout(); fig.savefig(plots / "pareto.png", dpi=150); plt.close(fig)

cp = df.dropna(subset=["logic_delay_ns", "net_delay_ns"]).sort_values(["synth_directive", "period_ns"])
if len(cp):
    fig, ax = plt.subplots(figsize=(8, 4.5))
    xs = np.arange(len(cp))
    ax.bar(xs, cp["logic_delay_ns"], label="logic delay")
    ax.bar(xs, cp["net_delay_ns"], bottom=cp["logic_delay_ns"], label="net (routing) delay")
    ax.set_xticks(xs); ax.set_xticklabels(cp["run"], rotation=60, ha="right", fontsize=7)
    ax.set_ylabel("Critical path delay (ns)"); ax.set_title("Critical path composition")
    ax.legend(fontsize=8); ax.grid(axis="y", alpha=0.3)
    fig.tight_layout(); fig.savefig(plots / "critical_path.png", dpi=150); plt.close(fig)

if loo_preds:
    fig, axes = plt.subplots(1, len(loo_preds), figsize=(4.2 * len(loo_preds), 4))
    axes = np.atleast_1d(axes)
    for ax, (t, (yt, yp)) in zip(axes, loo_preds.items()):
        ax.scatter(yt, yp)
        lo, hi = min(yt.min(), yp.min()), max(yt.max(), yp.max())
        ax.plot([lo, hi], [lo, hi], "k--", lw=0.8)
        ax.set_xlabel("Measured"); ax.set_ylabel("Predicted (leave-one-out)")
        ax.set_title(f"{targets[t]}\n{models[t][0]}", fontsize=9); ax.grid(alpha=0.3)
    fig.tight_layout(); fig.savefig(plots / "model_accuracy.png", dpi=150); plt.close(fig)

# ----------------------------------------------------------------- report
L = []
L.append("# PBL-2 Task 7: AI-based design parameter analysis\n")
L.append(f"Device: xc7z020clg484-1 (ZedBoard), out-of-context implementation. "
         f"{len(df)} runs over {df['period_ns'].nunique()} clock targets x {len(dirs)} synthesis directives.\n")
L.append("Power is Vivado's vectorless estimate (default toggle rates).\n")

L.append("## Measured results\n")
cols = ["run", "wns_ns", "fmax_mhz", "logic_levels", "luts", "lutram", "ffs",
        "total_power_w", "energy_per_instr_nJ", "runtime_ns"]
L.append(df[cols].round(3).to_markdown(index=False) + "\n")

L.append("## Model selection (leave-one-out cross-validation)\n")
for t, sc in scores.items():
    L.append(f"**{targets[t]}** - selected: {models[t][0]}\n")
    L.append("| Model | MAE | MAPE % |\n|---|---|---|")
    for n_, v in sc.items():
        L.append(f"| {n_} | {v['MAE']:.4g} | {v['MAPE_%']:.2f} |")
    L.append("")

L.append("## Which knobs matter (permutation importance)\n")
for t, imp in importance.items():
    L.append(f"**{targets[t]}**: " + ", ".join(f"{k} ({v:.3g})" for k, v in imp.items()) + "\n")

if phys:
    L.append("## Physics-informed power model: P = P_static + k * f\n")
    L.append("| Directive | P_static (W) | k (mW/MHz) | R^2 |\n|---|---|---|---|")
    for d, v in phys.items():
        L.append(f"| {d} | {v['P_static_W']:.4f} | {v['k_mW_per_MHz']:.4f} | {v['R2']:.4f} |")
    L.append("\nA near-1 R^2 confirms dynamic power scales linearly with frequency "
             "(P_dyn = a*C*V^2*f); k captures the design's effective switched capacitance.\n")

L.append("## Model-driven recommendations\n")
if recs:
    L.append("| Directive | Fastest predicted-safe period (ns) | Freq (MHz) | Pred. power (W) | Pred. energy/instr (nJ) |")
    L.append("|---|---|---|---|---|")
    for d, v in recs.items():
        L.append(f"| {d} | {v['fastest_safe_period_ns']} | {v['freq_mhz']} | "
                 f"{v.get('pred_power_w', '-')} | {v.get('pred_energy_per_instr_nJ', '-')} |")
    L.append("\nThese periods are interpolated by the model, including ones never run. "
             "Validate one by adding it to `periods` in sweep.tcl and comparing.\n")
L.append(f"**Measured Pareto-optimal runs (speed vs power, timing met):** {', '.join(pareto) or 'none'}\n")

if df["logic_frac"].notna().any():
    L.append("## Critical path\n")
    L.append(f"Logic levels: {int(df['logic_levels'].min())}-{int(df['logic_levels'].max())}. "
             f"Logic delay is {df['logic_frac'].mean()*100:.1f}% of the critical path on average; "
             f"the rest is routing. In a single-cycle design the path runs PC -> imem -> regfile "
             f"-> ALU -> dmem -> writeback, so pipelining is the next lever for Fmax.\n")

L.append("## Plots\n")
for p_ in sorted(plots.glob("*.png")):
    L.append(f"![{p_.stem}](plots/{p_.name})")

(out / "analysis_report.md").write_text("\n".join(L))
grid.to_csv(out / "design_space_predictions.csv", index=False)
(out / "analysis_summary.json").write_text(json.dumps(
    {"model_scores": scores, "importance": importance, "power_model": phys,
     "recommendations": recs, "pareto": pareto}, indent=2, default=float))

print(f"Analyzed {len(df)} runs.")
for t in models:
    print(f"  {targets[t]:22s} best model: {models[t][0]:18s} LOO MAE = {scores[t][models[t][0]]['MAE']:.4g}")
for d, v in recs.items():
    print(f"  {d:22s} -> fastest predicted-safe clock {v['freq_mhz']} MHz ({v['fastest_safe_period_ns']} ns)")
print(f"Report: {out/'analysis_report.md'}   Plots: {plots}/")
