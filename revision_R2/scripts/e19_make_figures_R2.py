"""E19 - New main figures of revision R2 (Elsevier artwork specifications, as in e06).

  Fig. 1  reference systems (laboratory flow channel; illustrative pipe circuit) and audit workflow
          - engineering schematic drawn with Matplotlib (replaces the earlier AI-assisted illustration)
  Fig. 2  benchmark of the removal kinetics against published experimental data (E15, E16)
  Fig. 3  robustness audit of the experimentally calibrated case and retrospective check (E17)
The former Figs. 5 and 6 are re-used unchanged as Figs. 4 and 5 (files copied under the new numbers);
the former Figs. 2-4 are moved to the Supplementary Material (Figs. S10-S12).
  Fig. S13  tests made after the calibration: curve at 75 degC, plate heat exchanger, other laboratories (E24)
"""
import os, sys, json, shutil
import numpy as np, pandas as pd
import matplotlib as mpl
mpl.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle, Circle, Polygon
from matplotlib.lines import Line2D

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
FIGROOT = os.path.abspath(os.path.join(HERE, "..", "..", "Figures"))
FIG_MAIN, FIG_SUP = os.path.join(FIGROOT, "main"), os.path.join(FIGROOT, "supplementary")
MM = 1 / 25.4
OI = dict(black="#000000", orange="#E69F00", sky="#56B4E9", green="#009E73", yellow="#F0E442",
          blue="#0072B2", verm="#D55E00", purple="#CC79A7", grey="#8C8C8C", navy="#1F3B6B")
mpl.rcParams.update({
    "font.family": "Arial", "font.size": 7.5, "axes.labelsize": 7.5, "axes.titlesize": 8,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "legend.fontsize": 6.5, "axes.linewidth": 0.6,
    "xtick.major.width": 0.6, "ytick.major.width": 0.6, "xtick.major.size": 2.5, "ytick.major.size": 2.5,
    "lines.linewidth": 1.0, "pdf.fonttype": 42, "ps.fonttype": 42, "svg.fonttype": "none",
    "axes.spines.top": False, "axes.spines.right": False, "legend.frameon": False, "savefig.dpi": 1000,
})
O = lambda f: os.path.join(OUT, f)
H_REF, FLOOR = 3.0, 95.0


def save(fig, folder, name, dpi=1000):
    base = os.path.join(folder, name)
    fig.savefig(base + ".pdf"); fig.savefig(base + ".svg")
    fig.savefig(base + ".tif", dpi=dpi, pil_kwargs={"compression": "tiff_lzw"})
    fig.savefig(base + "_preview600.png", dpi=600)
    plt.close(fig); print("saved", name)


def panel(ax, letter, x=-0.14, y=1.04):
    ax.text(x, y, f"({letter})", transform=ax.transAxes, fontsize=8.5, fontweight="bold", va="bottom")


# ============================================================================ Fig. 1
def rbox(ax, x, y, w, h, fc="#FFFFFF", ec="#333333", lw=0.8, ls="-", r=0.6):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad=0,rounding_size={r}", fc=fc, ec=ec, lw=lw, ls=ls))


def pipe(ax, pts, color="#333333", lw=1.3, ls="-", head=True):
    xs, ys = zip(*pts)
    ax.plot(xs[:-1] if False else xs, ys, color=color, lw=lw, ls=ls, solid_capstyle="butt", zorder=2)
    if head:
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
        ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-|>", mutation_scale=7, color=color, lw=0, shrinkA=0, shrinkB=0, zorder=3))


def pump(ax, x, y, r=1.6):
    ax.add_patch(Circle((x, y), r, fc="#F4F4F4", ec="#333333", lw=0.8, zorder=4))
    ax.add_patch(Polygon([(x - 0.7 * r, y + 0.6 * r), (x - 0.7 * r, y - 0.6 * r), (x + 0.9 * r, y)], fc="#333333", ec="none", zorder=5))


def fig1():
    fig = plt.figure(figsize=(190 * MM, 150 * MM))
    T = dict(fontsize=6.5, linespacing=1.2)
    # ------------------------------------------------------------------ (a) laboratory flow channel
    ax = fig.add_axes([0.005, 0.555, 0.47, 0.435]); ax.set_xlim(0, 100); ax.set_ylim(0, 60); ax.axis("off")
    ax.text(0, 59.5, "(a)", fontsize=8.5, fontweight="bold", va="top")
    ax.text(7, 59.5, "Experimental reference system: laboratory flow channel", fontsize=7.5, fontweight="bold", va="top")
    rbox(ax, 2, 18, 17, 22, fc="#FFF1DD")
    ax.text(10.5, 29, "NaOH tank\n0.5 wt%, 5 L\nT = 50–70 °C", ha="center", va="center", **T)
    pump(ax, 27, 22)
    ax.text(27, 17.2, "pump", ha="center", va="top", **T)
    pipe(ax, [(19, 22), (25.4, 22)], head=False); pipe(ax, [(28.6, 22), (34, 22), (34, 31), (40, 31)])
    # channel (side view)
    ax.add_patch(Rectangle((40, 27), 46, 8, fc="#EAF3FB", ec="#333333", lw=0.9, zorder=1))
    ax.add_patch(Rectangle((40, 25.2), 46, 1.8, fc="#9A9A9A", ec="#333333", lw=0.6, zorder=2))          # steel plate
    ax.add_patch(Rectangle((43, 27), 40, 2.6, fc="#C9A66B", ec="#7A5C2E", lw=0.5, zorder=3))           # deposit
    ax.add_patch(Rectangle((40, 22.6), 46, 2.6, fc="#F4B183", ec="#333333", lw=0.5, zorder=1))          # heater
    ax.text(63, 23.9, "heated support (wall temperature control)", ha="center", va="center", fontsize=5.8)
    ax.annotate("", xy=(51, 32.6), xytext=(44, 32.6), arrowprops=dict(arrowstyle="-|>", lw=0.8, color=OI["blue"]))
    ax.text(52, 32.6, "v = 0.5–23 cm s$^{-1}$", va="center", color=OI["blue"], fontsize=6.2)
    ax.text(60, 41.3, "channel 300 × 30 × 6 mm; stainless-steel plate (304, 2B)", ha="center", fontsize=6.2)
    ax.annotate("whey-protein deposit, h$_0$ = 2–3 mm\nresidual soil state S(t)", xy=(45, 28.3), xytext=(26, 47.5), fontsize=6.3, ha="center",
                arrowprops=dict(arrowstyle="-", lw=0.5, color="#7A5C2E", shrinkA=1, shrinkB=0), color="#5A3F12")
    ax.annotate("side-view camera:\nlayer thickness h(t)", xy=(83.5, 28.8), xytext=(88, 47.5), fontsize=6.3, ha="center",
                arrowprops=dict(arrowstyle="-|>", lw=0.6, color=OI["verm"], shrinkA=1), color=OI["verm"])
    pipe(ax, [(86, 31), (95, 31), (95, 12), (10.5, 12), (10.5, 18)], color="#666666", ls="--", lw=1.0)
    ax.text(52, 10.2, "recirculation (closed system) or once-through to drain (open system)", ha="center", va="top", fontsize=6.2, color="#444444")
    ax.annotate("UV–Vis: protein in\nsolution C(t)", xy=(95, 18), xytext=(80, 17.5), fontsize=6.3, ha="center", va="center",
                arrowprops=dict(arrowstyle="-|>", lw=0.6, color=OI["verm"]), color=OI["verm"])
    ax.text(50, 3.0, "Published measurements (Zhang et al., 2025): calibration and validation of the\nremoval kinetics (Fig. 2) and audit of the calibrated case (Fig. 3). Alkaline step only.",
            ha="center", va="center", fontsize=6.2, style="italic")
    # ------------------------------------------------------------------ (b) illustrative pipe circuit
    ax = fig.add_axes([0.495, 0.555, 0.50, 0.435]); ax.set_xlim(-3, 100); ax.set_ylim(0, 60); ax.axis("off")
    ax.text(0, 59.5, "(b)", fontsize=8.5, fontweight="bold", va="top")
    ax.text(6.5, 59.5, "Illustrative pipe circuit (assumed parameters)", fontsize=7.5, fontweight="bold", va="top")
    # phase bar
    x0, wtot, yb = 2, 96, 47.5
    for nm, sub, fr, col in [("1 Pre-rinse", "water, t$_{pre}$", 0.19, "#BFD7EA"), ("2 Alkaline wash", "NaOH at T, t$_{alk}$ (heated)", 0.33, "#F4B183"),
                             ("3 Intermediate rinse", "water, t$_{int}$", 0.27, "#DDEBF7"), ("4 Final rinse", "water, t$_{final}$", 0.21, "#BFD7EA")]:
        ax.add_patch(Rectangle((x0, yb), wtot * fr - 0.5, 6.4, fc=col, ec="#333333", lw=0.5))
        ax.text(x0 + wtot * fr / 2, yb + 4.4, nm, ha="center", va="center", fontsize=6.3, fontweight="bold")
        ax.text(x0 + wtot * fr / 2, yb + 1.7, sub, ha="center", va="center", fontsize=5.8)
        x0 += wtot * fr
    for y, lab, fc in [(34, "Fresh water\nT$_{in}$ 5–25 °C", "#E8F1FA"), (23, "Recovered\nwater", "#E8F1FA"), (12, "NaOH\nsolution", "#FFF1DD")]:
        rbox(ax, 1, y, 15, 9, fc=fc)
        ax.text(8.5, y + 4.5, lab, ha="center", va="center", **T)
        pipe(ax, [(16, y + 4.5), (21, y + 4.5), (21, 27.5)], head=False)
    pipe(ax, [(21, 27.5), (24.4, 27.5)], head=False)
    pump(ax, 26, 27.5)
    ax.text(26, 24.9, "pump, Q", ha="center", va="top", **T)
    pipe(ax, [(27.6, 27.5), (33, 27.5)])
    rbox(ax, 33, 22.5, 13, 10, fc="#FFF1DD")
    ax.plot([35, 37, 39, 41, 43, 44.5], [27.5, 30.5, 24.5, 30.5, 24.5, 27.5], color=OI["verm"], lw=0.9)
    ax.text(39.5, 21.2, "heater\n(alkaline step)", ha="center", va="top", **T)
    pipe(ax, [(46, 27.5), (52, 27.5)])
    # simulated domain: pipe section
    ax.add_patch(Rectangle((52, 25.2), 30, 4.6, fc="#EAF3FB", ec="#333333", lw=0.9, zorder=2))
    ax.add_patch(Rectangle((52, 29.1), 30, 0.7, fc="#C9A66B", ec="none", zorder=3)); ax.add_patch(Rectangle((52, 25.2), 30, 0.7, fc="#C9A66B", ec="none", zorder=3))
    ax.add_patch(Rectangle((49.3, 17.0), 35.4, 21.0, fc="none", ec=OI["green"], lw=1.0, ls=(0, (4, 2)), zorder=1))
    ax.text(67, 36.2, "simulated domain", ha="center", va="center", fontsize=6.3, color=OI["green"], fontweight="bold")
    ax.text(67, 32.6, "pipe wall, 22.2 mm i.d.", ha="center", va="center", fontsize=5.8)
    ax.text(67, 21.2, "lumped soil state S(t), S(0) = s$_0$\nv = 0.36–2.15 m s$^{-1}$", ha="center", va="center", fontsize=5.8, linespacing=1.2)
    pipe(ax, [(82, 27.5), (93, 27.5), (93, 13)])
    rbox(ax, 86, 5.5, 13, 7.5, fc="#F4F4F4")
    ax.text(92.5, 9.2, "drain /\neffluent", ha="center", va="center", **T)
    pipe(ax, [(88, 27.5), (88, 41), (39.5, 41), (39.5, 32.5)], color=OI["verm"], ls="--", lw=1.0)
    ax.text(62, 42.6, "heat recovery (η$_{heat}$)", ha="center", fontsize=6.2, color=OI["verm"])
    pipe(ax, [(86, 8), (-1.5, 8), (-1.5, 27.5), (1, 27.5)], color=OI["blue"], ls="--", lw=1.0)
    ax.text(50, 6.6, "water recovery (η$_{water}$)", ha="center", va="top", fontsize=6.2, color=OI["blue"])
    ax.text(50, 0.6, "Tanks, valves, fittings and the acid and disinfection steps are outside the simulated domain.", ha="center", va="bottom",
            fontsize=6.2, style="italic")
    # ------------------------------------------------------------------ (c) workflow
    ax = fig.add_axes([0.005, 0.005, 0.99, 0.525]); ax.set_xlim(0, 200); ax.set_ylim(0, 76); ax.axis("off")
    ax.text(0, 75.5, "(c)", fontsize=8.5, fontweight="bold", va="top")
    ax.text(7, 75.5, "Workflow of the framework", fontsize=7.5, fontweight="bold", va="top")

    def step(x, y, w, h, n, title, body, fc):
        rbox(ax, x, y, w, h, fc=fc, r=1.2)
        ax.text(x + 4.2, y + h - 4.5, str(n), color="white", fontsize=7, fontweight="bold", ha="center", va="center",
                bbox=dict(boxstyle="circle,pad=0.25", fc=OI["navy"], ec="none"))
        ax.text(x + 8.2, y + h - 4.5, title, fontsize=6.7, fontweight="bold", va="center")
        ax.text(x + 3, y + h - 9.2, body, fontsize=6.2, va="top", linespacing=1.22)

    w, h, y1, y2 = 36.6, 24, 45, 11
    xs = [2, 41.6, 81.2, 120.8, 160.4]
    row1 = [(1, "Model parameters", "coefficients and variable\nbounds: assumed (b) or\ncalibrated on experiments (a)", "#EAF6EF"),
            (2, "Mechanistic simulator", "soil removal, cleaning\nscore CS, water and energy\n(Simulink; closed form)", "#F4F4F4"),
            (3, "Virtual design", "5,000 scenarios; checks of\nsolver success and\nphysical feasibility", "#F4F4F4"),
            (4, "Surrogate models", "LSBoost models of the\nsimulator outputs", "#F4F4F4"),
            (5, "Nominal screening", "Pareto search and policy\nselection at the nominal\nsoil load", "#E8F1FA")]
    row2 = [(6, "Re-verification", "selected recipes\nre-simulated with the\nmechanistic simulator", "#F4F4F4"),
            (7, "Monte Carlo audit", "uncertainty sets U0–U3;\nlower tail of CS:\nq$_{0.10}$(CS) ≥ CS$_{min}$", "#FFF1DD"),
            (8, "Safety shield", "fixed rules admit or\nreject each recipe", "#FDECEA"),
            (9, "Admitted recipes", "only admitted recipes\nare retained for\nselection", "#E8F1FA"),
            (10, "Human review", "screening results;\nplant-specific validation\nremains required", "#F4F4F4")]
    for x, (n, title, body, fc) in zip(xs, row1):
        step(x, y1, w, h, n, title, body, fc)
    for x, (n, title, body, fc) in zip(xs[::-1], row2):
        step(x, y2, w, h, n, title, body, fc)
    for i in range(4):
        pipe(ax, [(xs[i] + w, y1 + h / 2), (xs[i + 1], y1 + h / 2)], lw=1.0)
    pipe(ax, [(xs[4] + w / 2 + 6, y1), (xs[4] + w / 2 + 6, y2 + h)], lw=1.0)
    for i in (4, 3, 2, 1):
        pipe(ax, [(xs[i], y2 + h / 2), (xs[i - 1] + w, y2 + h / 2)], lw=1.0)
    # audit-then-select: the recipes admitted in step 8 return to the selection of step 5
    pipe(ax, [(xs[2] + w / 2, y2 + h), (xs[2] + w / 2, 40.2), (xs[4] + w / 2 - 6, 40.2), (xs[4] + w / 2 - 6, y1)], color=OI["orange"], lw=1.2)
    ax.text(xs[2] + w / 2 + 2, 41.6, "audit-then-select: the audit is applied to all candidates before the selection", fontsize=6.2,
            color="#B37400", style="italic", va="bottom")
    ax.text(100, 4.6, "Verification (Sections 2.4, 3.1 and 3.2): the removal kinetics of step 1 were calibrated on, and compared with, published cleaning curves "
            "measured in system (a).", ha="center", va="center", fontsize=6.2, color=OI["verm"], style="italic")
    save(fig, FIG_MAIN, "Fig1_reference_systems_and_workflow")


# ============================================================================ Fig. 2
def fig2():
    ovp = pd.read_csv(O("E16_observed_vs_predicted.csv"))
    per = pd.read_csv(O("E16_per_curve_fits.csv"))
    val = pd.read_csv(O("E16_validation_metrics.csv"))
    fig, axs = plt.subplots(2, 3, figsize=(190 * MM, 122 * MM))
    fig.subplots_adjust(left=0.065, right=0.985, top=0.925, bottom=0.085, wspace=0.34, hspace=0.42)
    cols = [OI["blue"], OI["verm"], OI["green"], OI["purple"], OI["orange"], OI["black"]]

    def curves(ax, ids, labels, xmax):
        for cid, lab, c in zip(ids, labels, cols):
            g0 = ovp[(ovp.curve == cid) & (ovp.model == "M0")].sort_values("t_min")
            g1 = ovp[(ovp.curve == cid) & (ovp.model == "M1")].sort_values("t_min")
            ax.plot(g0.t_min, g0.y_obs, "o", ms=1.9, mfc=c, mec="none", alpha=0.75, label=lab)
            ax.plot(g0.t_min, g0.y_pred, "-", color=c, lw=1.1)
            ax.plot(g1.t_min, g1.y_pred, "--", color=c, lw=0.8)
        ax.set_xlim(0, xmax); ax.set_ylim(0, 1.08); ax.set_xlabel("Time (min)"); ax.set_ylabel("Residual soil, S/S$_0$ (–)")

    curves(axs[0, 0], ["Z6b:v=0.5", "Z6b:v=1.5", "Z6b:v=23.0"], ["0.5 cm s$^{-1}$", "1.5 cm s$^{-1}$", "23 cm s$^{-1}$"], 22)
    axs[0, 0].legend(loc="upper right", handletextpad=0.2, title="70 °C", title_fontsize=6.5)
    curves(axs[0, 1], ["Z6b:v=1.0", "Z6c:T=60", "Z6c:T=50"], ["70 °C", "60 °C", "50 °C"], 60)
    axs[0, 1].legend(loc="upper right", handletextpad=0.2, title="1 cm s$^{-1}$", title_fontsize=6.5)
    curves(axs[0, 2], ["Z9a:v=0.5", "Z11a:v=1.0", "Z11d:v=23.0"], ["0.5 cm s$^{-1}$", "1 cm s$^{-1}$", "23 cm s$^{-1}$"], 33)
    axs[0, 2].legend(loc="upper right", handletextpad=0.2, title="70 °C, whole channel", title_fontsize=6.5)
    hl = [Line2D([], [], color="k", lw=1.1, label="uniform removal"), Line2D([], [], color="k", lw=0.8, ls="--", label="first order")]
    axs[0, 1].add_artist(axs[0, 1].legend(handles=hl, loc="lower left", bbox_to_anchor=(0.30, 0.52), handlelength=1.8)) if False else None
    fig.legend(handles=[Line2D([], [], marker="o", ls="", ms=2.5, color="k", label="observed"), *hl], loc="upper right", ncol=3,
               bbox_to_anchor=(0.985, 1.005), handletextpad=0.4, columnspacing=1.5)
    for a, l in zip(axs[0], "abc"):
        panel(a, l)

    # (d) parity of the time to 90% removal
    ax = axs[1, 0]
    v = val[val.role != "duplicate"]
    roles = [("calibration", "o", "calibration"), ("validation: other axial position", "s", "other axial positions"),
             ("validation: whole-channel protein (UV-Vis)", "^", "whole channel (UV–Vis)"), ("validation: independent laboratory", "D", "independent laboratory")]
    for model, fc in (("M0", None), ("M1", "white")):
        for role, mk, lab in roles:
            g = v[(v.model == model) & (v.role == role)]
            ax.plot(g.t90_obs_min, g.t90_pred_min, mk, ms=3.6, mec=OI["blue"] if model == "M0" else OI["verm"],
                    mfc=(OI["blue"] if fc is None else fc), mew=0.7, label=lab if model == "M0" else None)
    xx = np.array([3, 300])
    ax.plot(xx, xx, "-", color="#555555", lw=0.7); ax.plot(xx, 1.5 * xx, ":", color="#888888", lw=0.6); ax.plot(xx, xx / 1.5, ":", color="#888888", lw=0.6)
    ax.set_xscale("log"); ax.set_yscale("log"); ax.set_xlim(3, 900); ax.set_ylim(3, 300)
    ax.set_xlabel("Observed time to 90% removal (min)"); ax.set_ylabel("Predicted time to 90% removal (min)")
    h1, l1 = ax.get_legend_handles_labels()
    ax.legend(h1 + [Line2D([], [], marker="o", ls="", ms=3.6, mfc=OI["blue"], mec=OI["blue"]), Line2D([], [], marker="o", ls="", ms=3.6, mfc="white", mec=OI["verm"])],
              l1 + ["uniform removal", "first order"], loc="lower right", handletextpad=0.2, labelspacing=0.25, fontsize=6)
    panel(ax, "d")

    # (e) structural test
    ax = axs[1, 1]
    use = per[per.role != "duplicate"]
    names = [("M1_rmse", "first\norder"), ("M1L_rmse", "first order\n+ lag"), ("M0_rmse", "uniform"), ("M2_rmse", "two-stage")]
    rng = np.random.default_rng(1)
    for i, (c, lab) in enumerate(names):
        y = use[c].to_numpy()
        ax.plot(i + rng.uniform(-0.13, 0.13, len(y)), y, "o", ms=2.6, mfc=OI["grey"], mec="none", alpha=0.8)
        ax.plot([i - 0.25, i + 0.25], [np.median(y)] * 2, "-", color=OI["verm"], lw=1.4)
        ax.text(i + 0.29, np.median(y), f"{np.median(y):.3f}", ha="left", va="center", fontsize=6.2, color=OI["verm"])
    ax.set_xticks(range(4)); ax.set_xticklabels([n for _, n in names]); ax.set_ylim(0, 0.14); ax.set_xlim(-0.5, 3.75)
    ax.set_ylabel("RMSE of the fit to each curve, S/S$_0$ (–)")
    panel(ax, "e")

    # (f) independent laboratory
    ax = axs[1, 2]
    cid = "W10a_protein:protein"
    g0 = ovp[(ovp.curve == cid) & (ovp.model == "M0")].sort_values("t_min"); g1 = ovp[(ovp.curve == cid) & (ovp.model == "M1")].sort_values("t_min")
    r = per[per.curve == cid].iloc[0]
    tt = np.linspace(0, 92, 300)
    ax.plot(g0.t_min, g0.y_obs, "o", ms=3, mfc=OI["black"], mec="none", label="observed (23.5 °C, WPI gel)")
    ax.plot(tt, np.clip(1 - tt / r.M0_tc_min, 0, None), "-", color=OI["green"], lw=1.1, label="uniform removal, fitted")
    ax.plot(tt, np.exp(-r.M1_k_per_min * tt), "--", color=OI["green"], lw=0.9, label="first order, fitted")
    ax.plot(g0.t_min, g0.y_pred, "-", color=OI["blue"], lw=1.1, label="uniform removal, predicted")
    ax.plot(g1.t_min, g1.y_pred, "--", color=OI["verm"], lw=0.9, label="first order, predicted")
    ax.set_xlim(0, 92); ax.set_ylim(0, 1.62); ax.set_yticks([0, 0.2, 0.4, 0.6, 0.8, 1.0]); ax.set_xlabel("Time (min)"); ax.set_ylabel("Residual soil, S/S$_0$ (–)")
    ax.legend(loc="upper right", handletextpad=0.3, labelspacing=0.25, fontsize=5.8)
    panel(ax, "f")
    save(fig, FIG_MAIN, "Fig2_experimental_benchmark")


# ============================================================================ Fig. 3
def fig3():
    ovp = pd.read_csv(O("E16_observed_vs_predicted.csv")); ovp = ovp[ovp.model == "M0"]
    per = pd.read_csv(O("E16_per_curve_fits.csv")).set_index("curve")
    grid = pd.read_csv(O("E17_required_wash_time.csv"))
    retro = pd.read_csv(O("E17_retrospective_check_crossvalidated.csv"))     # cross-validated wash times (panels a, b)
    cand = pd.read_csv(O("E17_candidates.csv"))
    sel = pd.read_csv(O("E17_selected_recipes.csv"))
    fig, axs = plt.subplots(2, 2, figsize=(190 * MM, 140 * MM))
    fig.subplots_adjust(left=0.075, right=0.985, top=0.955, bottom=0.075, wspace=0.42, hspace=0.34)
    rule_col = dict(nominal=OI["grey"], U0=OI["sky"], U3=OI["blue"])

    # (a) observed runs at 70 degC, 1 cm/s vs the three wash times
    ax = axs[0, 0]
    ids = [("Z6a:x=12cm", "local, x = 12 cm"), ("Z6b:v=1.0", "local, x = 16 cm"), ("Z6a:x=19cm", "local, x = 19 cm"), ("Z6a:x=22cm", "local, x = 22 cm"),
           ("Z9a:v=1.0", "whole channel, run 1"), ("Z11a:v=1.0", "whole channel, run 2")]
    cc = [OI["navy"], OI["blue"], OI["sky"], OI["green"], OI["orange"], OI["verm"]]
    for (cid, lab), c in zip(ids, cc):
        g = ovp[ovp.curve == cid].sort_values("t_min")
        cs = 100 * (1 - g.y_obs * per.loc[cid, "h0_mm"] / H_REF)
        t = np.r_[g.t_min, 26] if g.t_min.max() < 26 else g.t_min
        cs = np.r_[cs, 100] if g.t_min.max() < 26 else cs
        ax.plot(t, cs, "-" if "local" in lab else "--", color=c, lw=1.0, label=lab)
    c70 = retro[(retro.model == "M0") & (retro.T_C == 70) & (retro.v_cm_s == 1.0)].groupby("wash_time_rule").wash_time_min.first()
    gr = {"t_nominal_min": c70["nominal"], "t_U0_min": c70["U0"], "t_U3_min": c70["U3"]}
    for key, lab in (("t_nominal_min", "nominal"), ("t_U0_min", "U0"), ("t_U3_min", "U3")):
        k = "nominal" if "nominal" in key else lab
        ax.axvline(gr[key], color=rule_col[k], lw=1.2, ls="-")
        name = "nominal" if k == "nominal" else "robust, " + lab
        ax.text(gr[key] + 0.3, 17, f"{name}: {gr[key]:.1f} min", fontsize=6.2, rotation=90,
                color=rule_col[k] if k != "nominal" else "#555555", va="bottom", ha="left")
    ax.axhline(FLOOR, color="k", lw=0.6, ls=":"); ax.text(25.8, FLOOR - 1.0, "floor, CS = 95%", fontsize=6.2, ha="right", va="top")
    ax.set_xlim(0, 26); ax.set_ylim(15, 103); ax.set_xlabel("Wash time (min)"); ax.set_ylabel("Observed cleaning score, CS (%)")
    ax.legend(loc="upper left", bbox_to_anchor=(0.0, 0.90), handlelength=1.8, labelspacing=0.25, fontsize=6)
    panel(ax, "a")

    # (b) retrospective check, all 17 observed curves
    ax = axs[0, 1]
    r = retro[retro.model == "M0"]
    rng = np.random.default_rng(3)
    for i, k in enumerate(["nominal", "U0", "U3"]):
        y = r[r.wash_time_rule == k].observed_CS.to_numpy()
        ax.plot(i + rng.uniform(-0.16, 0.16, len(y)), y, "o", ms=3.4, mfc=rule_col[k], mec="white", mew=0.3)
        ax.text(i, 60.5, f"{int((y >= FLOOR).sum())} of {len(y)}\ncurves ≥ 95%", ha="center", va="center", fontsize=6.6)
    ax.axhline(FLOOR, color="k", lw=0.6, ls=":")
    ax.set_xticks(range(3)); ax.set_xticklabels(["nominal wash time", "robust, U0", "robust, U3"]); ax.set_xlim(-0.5, 2.5); ax.set_ylim(57, 101.5)
    ax.set_ylabel("Observed CS at the prescribed wash time (%)")
    panel(ax, "b")

    # (c) required wash time vs velocity at 70 degC, with observed times to reach the floor
    ax = axs[1, 0]
    g = grid[(grid.model == "M0") & (grid.T_C == 70)].sort_values("v_cm_s")
    g1 = grid[(grid.model == "M1") & (grid.T_C == 70)].sort_values("v_cm_s")
    ax.plot(g.v_cm_s, g.t_nominal_min, "-o", color=rule_col["nominal"], ms=2.5, label="nominal")
    ax.plot(g.v_cm_s, g.t_U0_min, "-o", color=rule_col["U0"], ms=2.5, label="robust, U0")
    ax.plot(g.v_cm_s, g.t_U3_min, "-o", color=rule_col["U3"], ms=2.5, label="robust, U3")
    ax.plot(g1.v_cm_s, g1.t_nominal_min, "--", color=OI["verm"], lw=0.9, label="nominal, first-order law")
    obs = []
    for cid, row in per[(per.T_C == 70) & (per.role != "duplicate") & ~per.role.str.contains("independent")].iterrows():
        gg = ovp[ovp.curve == cid].sort_values("t_min")
        lim = 0.05 * H_REF / row.h0_mm
        below = np.where(gg.y_obs.to_numpy() <= lim)[0]
        tcl = gg.t_min.to_numpy()[below[0]] if len(below) else row.t_end_obs_min
        obs.append((row.v_cm_s, tcl, row.kind))
    obs = pd.DataFrame(obs, columns=["v", "t", "kind"])
    for kind, mk, lab in (("thickness", "x", "observed, local thickness"), ("protein", "+", "observed, whole channel")):
        o = obs[obs.kind == kind]
        ax.plot(o.v, o.t, mk, color="k", ms=4.5, mew=0.9, ls="", label=lab)
    ax.set_xscale("log"); ax.set_yscale("log"); ax.set_xlabel("Mean velocity (cm s$^{-1}$)"); ax.set_ylabel("Wash time to reach CS ≥ 95% (min)")
    ax.set_xticks([0.5, 1, 2, 5, 10, 23]); ax.set_xticklabels(["0.5", "1", "2", "5", "10", "23"]); ax.set_yticks([5, 10, 20, 40]); ax.set_yticklabels(["5", "10", "20", "40"])
    ax.minorticks_off(); ax.legend(loc="upper right", labelspacing=0.25, handlelength=1.8, fontsize=6)
    panel(ax, "c")

    # (d) wash times prescribed by the two rate laws at 70 degC, 1 cm/s vs the observed range
    ax = axs[1, 1]
    gm0 = grid[(grid.model == "M0") & (grid.T_C == 70) & (grid.v_cm_s == 1.0)].iloc[0]
    gm1 = grid[(grid.model == "M1") & (grid.T_C == 70) & (grid.v_cm_s == 1.0)].iloc[0]
    o1 = obs[np.isclose(obs.v, 1.0)].t
    ax.axvspan(o1.min(), o1.max(), color="#DDDDDD", zorder=0)
    ax.text(0.5 * (o1.min() + o1.max()), 6.62, "observed\n(six curves)", ha="center", va="top", fontsize=6.2, color="#444444")
    bars = [("uniform removal, nominal", gm0.t_nominal_min, rule_col["nominal"]), ("uniform removal, robust U0", gm0.t_U0_min, rule_col["U0"]),
            ("uniform removal, robust U3", gm0.t_U3_min, rule_col["U3"]), ("first order, nominal", gm1.t_nominal_min, "#F0B48A"),
            ("first order, robust U0", gm1.t_U0_min, "#E58A4E"), ("first order, robust U3", gm1.t_U3_min, OI["verm"])]
    for i, (lab, val_, c) in enumerate(bars):
        ax.barh(5 - i, val_, color=c, height=0.62, zorder=2)
        ax.text(val_ + 0.5, 5 - i, f"{val_:.1f}", va="center", fontsize=6.4)
    ax.set_yticks(range(6)); ax.set_yticklabels([b[0] for b in bars][::-1]); ax.set_ylim(-0.6, 6.75); ax.set_xlim(0, 47)
    ax.set_xlabel("Prescribed alkaline wash time at 70 °C and 1 cm s$^{-1}$ (min)")
    ax.tick_params(axis="y", length=0)
    panel(ax, "d", x=-0.42)
    save(fig, FIG_MAIN, "Fig3_calibrated_case_audit")


def renumber():
    """Former Figs. 5 and 6 become Figs. 4 and 5; former Figs. 2-4 become Supplementary Figs. S10-S12 (files copied, not redrawn)."""
    mp = [(FIG_MAIN, "Fig5_extended_MC_audit", FIG_MAIN, "Fig4_MC_audit_illustrative_case"),
          (FIG_MAIN, "Fig6_price_of_robustness", FIG_MAIN, "Fig5_cost_of_robustness_illustrative_case"),   # regenerated in R2: label 'cleaning floor' 
          (FIG_MAIN, "Fig2_sensitivity_verification", FIG_SUP, "FigS10_sensitivity_verification"),
          (FIG_MAIN, "Fig3_surrogate_parity", FIG_SUP, "FigS11_surrogate_parity"),
          (FIG_MAIN, "Fig4_pareto_fronts", FIG_SUP, "FigS12_pareto_fronts")]
    for sd, s, dd, d in mp:
        for ext in (".pdf", ".svg", ".tif", "_preview600.png"):
            a = os.path.join(sd, s + ext)
            if os.path.exists(a):
                shutil.copy2(a, os.path.join(dd, d + ext))
    print("renumbered copies written")


def figS13():
    """Supplementary Fig. S13 - tests made after the calibration had been fixed (E24)."""
    dig = pd.read_csv(O("E24_digitised_Zhang2026.csv"))
    s24 = json.load(open(O("E24_summary.json")))
    phe = pd.read_csv(O("E24_plate_heat_exchanger_test.csv"))
    flx = pd.read_csv(O("E24_plateau_flux_other_laboratories.csv"))
    A = s24["A_flat_channel_75C"]
    fig, axs = plt.subplots(1, 3, figsize=(190 * MM, 68 * MM))
    fig.subplots_adjust(left=0.065, right=0.99, top=0.90, bottom=0.165, wspace=0.36)
    rule_col = dict(nominal=OI["grey"], U0=OI["sky"], U3=OI["blue"])

    # (a) curve at 75 degC, 23.65 cm/s: observed cleaning score, predictions and prescribed wash times
    ax = axs[0]
    g = dig[dig.panel == "Z26_8b"].sort_values("t_or_x")
    h0 = A["h0_mm"]
    ax.plot(g.t_or_x, 100 * (1 - g.value / H_REF), "o", ms=2.2, mfc="k", mec="none", label="observed")
    tt = np.linspace(0, 12.5, 400)
    ax.plot(tt, 100 * (1 - np.maximum(h0 - A["M0"]["rate_pred"] * tt, 0) / H_REF), "-", color=OI["blue"], label="predicted, uniform removal")
    ax.plot(tt, 100 * (1 - h0 * np.exp(-A["M1"]["rate_pred"] * tt) / H_REF), "--", color=OI["verm"], label="predicted, first order")
    chk = A["M0"]["audit_rule_at_unseen_condition"]
    for k, lab in (("nominal", "nominal"), ("U0", "robust, U0"), ("U3", "robust, U3")):
        tw = chk[k]["wash_time_min"]
        ax.axvline(tw, color=rule_col[k], lw=1.1)
        ax.text(tw + 0.12, 8, f"{lab}: {tw:.1f} min", fontsize=5.8, rotation=90, va="bottom", ha="left", color=rule_col[k] if k != "nominal" else "#555555")
    ax.axhline(FLOOR, color="k", lw=0.6, ls=":")
    ax.set_xlim(0, 12.5); ax.set_ylim(5, 103); ax.set_xlabel("Wash time (min)"); ax.set_ylabel("Cleaning score, CS (%)")
    ax.legend(loc="center right", bbox_to_anchor=(1.02, 0.60), fontsize=5.8, handlelength=1.6, labelspacing=0.25)
    panel(ax, "a", x=-0.19)

    # (b) plate heat exchanger: observed alkaline cleaning time against uniform removal at the flat-channel rate
    ax = axs[1]
    p5 = phe[phe.within_model_scope]
    for ser, mk, lab in (("v_cm_s", "o", "velocity series, 80 °C"), ("T_C", "s", "temperature series, 27.5 cm s$^{-1}$")):
        q_ = p5[p5.series == ser]
        ax.plot(q_.t_alkaline_obs_min, q_.t_uniform_pred_min, mk, ms=4, mfc=OI["blue"] if ser == "v_cm_s" else OI["orange"], mec="white", mew=0.4, ls="", label=lab)
    lim = np.array([0.4, 40.0])
    ax.plot(lim, lim, "-", color="k", lw=0.7)
    for f_, ls_ in ((10, ":"),):
        ax.plot(lim, lim / f_, ls_, color="k", lw=0.6)
    ax.text(26, 30, "1:1", fontsize=6, ha="right", va="bottom"); ax.text(6.2, 0.56, "1:10", fontsize=6, ha="left", va="top")
    ax.set_xscale("log"); ax.set_yscale("log"); ax.set_xlim(0.4, 40); ax.set_ylim(0.4, 40)
    ax.set_xticks([1, 10]); ax.set_xticklabels(["1", "10"]); ax.set_yticks([1, 10]); ax.set_yticklabels(["1", "10"])
    ax.set_xlabel("Observed alkaline cleaning time (min)"); ax.set_ylabel("Predicted, uniform removal (min)")
    ax.legend(loc="upper left", fontsize=5.8, handletextpad=0.3, labelspacing=0.25)
    panel(ax, "b", x=-0.19)

    # (c) plateau removal flux in other laboratories against the calibrated law per unit of dry matter
    ax = axs[2]
    for key, mk, c, lab in (("Gillham", "D", OI["green"], "fouling deposit, tube (Gillham et al., 1999)"),
                            ("Table 1", "^", OI["purple"], "gel film, 35–75 °C (Xin et al., 2004)"),
                            ("Table 2", "v", OI["verm"], "gel film, 0.09–0.46 m s$^{-1}$ (Xin et al., 2004)")):
        q_ = flx[flx.source.str.contains(key)]
        for inside in (True, False):
            r_ = q_[q_.inside_calibrated_T_and_v == inside]
            ax.plot(r_.flux_obs_g_m2_s, r_.flux_pred_g_dry_m2_s, mk, ms=4, mfc=c if inside else "white", mec=c, mew=0.8, ls="",
                    label=lab if inside else None)
    lim = np.array([0.05, 2.0])
    ax.plot(lim, lim, "-", color="k", lw=0.7); ax.plot(lim, 2 * lim, ":", color="k", lw=0.6)
    ax.text(1.7, 1.45, "1:1", fontsize=6, ha="right", va="top"); ax.text(0.80, 1.85, "2:1", fontsize=6, ha="right", va="top")
    ax.set_xscale("log"); ax.set_yscale("log"); ax.set_xlim(0.05, 2); ax.set_ylim(0.05, 2)
    ax.set_xticks([0.1, 1]); ax.set_xticklabels(["0.1", "1"]); ax.set_yticks([0.1, 1]); ax.set_yticklabels(["0.1", "1"])
    ax.set_xlabel("Observed plateau flux (g m$^{-2}$ s$^{-1}$)"); ax.set_ylabel("Predicted flux of dry matter (g m$^{-2}$ s$^{-1}$)")
    ax.legend(loc="lower right", fontsize=5.4, handletextpad=0.3, labelspacing=0.25)
    panel(ax, "c", x=-0.21)
    save(fig, FIG_SUP, "FigS13_tests_beyond_calibration")


if __name__ == "__main__":
    which = sys.argv[1:] or ["fig1", "fig2", "fig3", "figS13"]
    for w in which:
        globals()[w]()
