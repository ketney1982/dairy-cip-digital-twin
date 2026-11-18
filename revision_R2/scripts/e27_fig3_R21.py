"""E27 - Fig. 3 of revision R2: panel (b) distinguishes observed outcomes from wash times that lie after the last
measured point of a curve (filled markers: the wash time lies within the measured curve, so the cleaning score was
observed; open markers: the wash time lies after the last measured point, where nothing was observed; they are
plotted at the score of the last measured point, column last_measured_CS of e17).
Implementation: the Fig. 3 code of e19 is re-used and only the block of panel (b) is replaced."""
import os, sys, re, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "e19_make_figures_R2.py"), encoding="utf-8").read()

NEW_B = '''    # (b) retrospective check, 16 curves; open symbols: wash time after the last measured point (not observed at that
    # time; plotted at the score of the last measured point)
    ax = axs[0, 1]
    r = retro[retro.model == "M0"].copy()
    r["after"] = ~r.within_record.astype(bool)
    rng = np.random.default_rng(3)
    for i, k in enumerate(["nominal", "U0", "U3"]):
        s = r[r.wash_time_rule == k]
        x = i + rng.uniform(-0.16, 0.16, len(s))
        aft = s.after.to_numpy(); yv = np.where(aft, s.last_measured_CS.to_numpy(), s.observed_CS.to_numpy())
        ax.plot(x[~aft], yv[~aft], "o", ms=3.6, mfc=rule_col[k], mec="white", mew=0.3)
        ax.plot(x[aft], yv[aft], "o", ms=3.6, mfc="white", mec=rule_col[k], mew=0.9)
        n_fail = int(((yv < FLOOR) & ~aft).sum()); n_ok = int(((yv >= FLOOR) & ~aft).sum()); n_aft = int(aft.sum())
        n_last = int(((yv >= FLOOR) & aft).sum())
        ax.text(i, 54.6, f"observed < 95%: {n_fail}\\nobserved \\u2265 95%: {n_ok}\\nafter last point: {n_aft}\\n(\\u2265 95% at last point: {n_last})",
                ha="center", va="center", fontsize=6.0)
    ax.axhline(FLOOR, color="k", lw=0.6, ls=":")
    ax.plot([], [], "o", ms=3.6, mfc="#555555", mec="white", label="score observed at the wash time")
    ax.plot([], [], "o", ms=3.6, mfc="white", mec="#555555", mew=0.9, label="wash time after last measured point\\n(score of the last measured point)")
    ax.legend(loc="lower right", bbox_to_anchor=(1.0, 0.19), fontsize=5.6, handletextpad=0.3, labelspacing=0.3)
    ax.set_xticks(range(3)); ax.set_xticklabels(["nominal wash time", "robust, U0", "robust, U3"]); ax.set_xlim(-0.5, 2.5); ax.set_ylim(50, 101.5)
    ax.set_ylabel("CS at the prescribed wash time (%)")
    panel(ax, "b")

'''
a = src.index("    # (b) retrospective check, all 17 observed curves")
b = src.index("    # (c) required wash time vs velocity")
src2 = src[:a] + NEW_B + src[b:]
# only Fig. 3, outputs to a separate folder
src2 = src2.replace('FIGROOT = os.path.abspath(os.path.join(HERE, "..", "..", "Figures"))',
                    'FIGROOT = os.path.abspath(os.path.join(HERE, "..", "..", "Figures_R21"))')
code = compile(src2, "e19_patched", "exec")
ns = {"__name__": "e19_patched", "__file__": os.path.join(HERE, "e19_make_figures_R2.py")}
exec(code, ns)
os.makedirs(ns["FIG_MAIN"], exist_ok=True); os.makedirs(ns["FIG_SUP"], exist_ok=True)
ns["fig3"]()
