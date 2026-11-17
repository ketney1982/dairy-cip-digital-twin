# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Conservative confirmation of the audit-then-select recipes (revision R1).

Run after src/run_robustness_audit.py (it reads results/candidate_q10.npz).

The audit admits a recipe when the point estimate of q0.10(CS) from M Monte Carlo
draws reaches the floor. Close to the floor this estimate carries sampling error
(Supplementary Table S16). Here every nominally feasible candidate is re-audited
with an independent sample of M = 10,000 draws (seed SEED + 202, the independent
sample of Supplementary Table S16), and a recipe is *confirmed* only if the lower
limit of the distribution-free (order-statistic) 95% confidence interval of
q0.10(CS) reaches the floor; i.e. the point estimate is replaced by a
conservative lower confidence bound.

1. Confirmation test of the recipes already selected (Tables 4 and 5).
2. Conservative audit-then-select: the weighted policy selection is repeated
   among the confirmed candidates, without and with the minimum-velocity screen
   (v >= 1.5 m/s in the 22.2-mm reference tube); each selected recipe is then
   checked once more with a further independent sample (seed SEED + 303).

For the full profile-specific hygiene-priority criterion, q0.90(Rhyg) <= 0.1, which
is equivalent to q0.10(CS) >= 99.5% because both indicators are monotonic
functions of the same residual soil, the same rule is applied with the floor 99.5%.

Output: results/conservative_confirmation.csv (Supplementary Table S17)
"""
import os, json
import numpy as np, pandas as pd
from cip_closed_form import src, simulate, simulate_X, VARS, LB, UB, matlab_rand
from run_robustness_audit import draws, realised, SEED
from run_audit_benchmarks import select, os_interval, velocity, D_TUBE

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")
KEYS = ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]
M = 10000
SEED_CONFIRM = SEED + 202        # independent M = 10,000 sample of Supplementary Table S16
SEED_RECHECK = SEED + 303        # further independent sample for the re-selected recipes
Q_MIN = 1.5 * np.pi / 4 * D_TUBE ** 2 * 3600.0


def q10_with_interval(X, d, chunk=100):
    """Point estimate (linear interpolation, as in the audit) and distribution-free
    95% interval of q0.10(CS) for every row of X under the draws d."""
    lo, hi = os_interval(len(d["s0"]))
    dd = {k: v[None, :] for k, v in d.items()}
    q, ql, qh = (np.empty(len(X)) for _ in range(3))
    for a in range(0, len(X), chunk):
        Xb = X[a:a + chunk]
        T, Q, C = realised(Xb[:, [0]], Xb[:, [1]], Xb[:, [6]], dd)
        cs = simulate(T, Q, Xb[:, [2]], Xb[:, [3]], Xb[:, [4]], Xb[:, [5]], C, dd["s0"], Xb[:, [8]], Xb[:, [9]],
                      T_in=dd["T_in"], k_cal=dd["k_cal"], alpha_T=dd["alpha_T"], beta_Q=dd["beta_Q"],
                      gamma=dd["gamma"])["cleaning_score"]
        q[a:a + chunk] = np.quantile(cs, 0.10, axis=1)
        part = np.partition(cs, [lo - 1, hi - 1], axis=1)
        ql[a:a + chunk], qh[a:a + chunk] = part[:, lo - 1], part[:, hi - 1]
    return q, ql, qh


if __name__ == "__main__":
    U = matlab_rand(42, 30000, 10)
    Xc = LB + U * (UB - LB)
    Xc[:, 7] = 0.5
    Y = simulate_X(Xc)
    caps = {"balanced_default": Y["cleaning_score"] >= 95,
            "cod_discharge_limit": (Y["cleaning_score"] >= 95) & (Y["COD_mgL"] <= 700),
            "hygiene_priority": (Y["cleaning_score"] >= 98) & (Y["hygienic_risk"] <= 0.1)}
    fast = Xc[:, 1] >= Q_MIN
    z = np.load(src("candidate_q10.npz"))                       # original audit, M = 1,000
    q_orig = {"U0": z["U0"], "U3": z["U3"]}
    r_orig = {"U0": z["Rhyg_q90_U0"], "U3": z["Rhyg_q90_U3"]}

    # independent M = 10,000 audit of all nominally feasible candidates, with intervals
    feas = np.where(caps["balanced_default"])[0]                 # contains the other profiles
    est = {}
    for lev in ("U0", "U3"):
        d = draws(lev, M, np.random.default_rng(SEED_CONFIRM))
        q, ql, qh = (np.full(len(Xc), np.nan) for _ in range(3))
        q[feas], ql[feas], qh[feas] = q10_with_interval(Xc[feas], d)
        est[lev] = (q, ql, qh)
        print(lev, "independent M = 10,000 audit done")

    def recheck(j, lev):
        d = draws(lev, M, np.random.default_rng(SEED_RECHECK))
        q, ql, qh = q10_with_interval(Xc[[j]], d, chunk=1)
        return float(q[0]), float(ql[0]), float(qh[0])

    def row(part, prof, screening, floor, lev, j, n_nom, n_adm, n_conf=None, recheck_j=False):
        q, ql, qh = (v[j] for v in est[lev])
        r = dict(part=part, profile=prof, screening=screening, uncertainty=lev, floor=floor,
                 n_nominal_feasible=int(n_nom), n_admitted=None if n_adm is None else int(n_adm),
                 n_confirmed=None if n_conf is None else int(n_conf), index=int(j))
        r.update({v: Xc[j, i] for i, v in enumerate(VARS)})
        r.update({k: Y[k][j] for k in KEYS})
        r.update(velocity_m_s=float(velocity(Xc[j, 1])), q10_original_M1000=float(q_orig[lev][j]),
                 q10_M10000=float(q), q10_M10000_CI95_low=float(ql), q10_M10000_CI95_high=float(qh),
                 confirmed=bool(ql >= floor))
        if recheck_j:
            a, b, c = recheck(j, lev)
            r.update(q10_recheck_M10000=a, q10_recheck_CI95_low=b, q10_recheck_CI95_high=c,
                     confirmed_recheck=bool(b >= floor))
        return r

    rows = []
    # ------------------------------------------- 1. confirmation of the reported selections
    rec = json.load(open(src("policy_recipes_unrounded.json")))
    for prof, x in rec.items():                                   # Table 4 (recipes of Table 3)
        x = np.array([x[v] for v in VARS], float)
        j = int(np.argmin(np.max(np.abs((Xc - x) / (UB - LB)), axis=1)))
        for lev in ("U0", "U3"):
            rows.append(row("1 confirmation of reported selection", prof, "policy recipe (Table 4)", 95.0,
                            lev, j, caps[prof].sum(), None))
    screens = {}
    for prof, m in caps.items():                                  # Table 5 audit-then-select rows
        for lev in ("U0", "U3"):
            screens[(prof, lev)] = m & (q_orig[lev] >= 95)
        screens[(prof, "U3", "min_velocity")] = m & fast & (q_orig["U3"] >= 95)
        screens[(prof, "U0", "min_velocity")] = m & fast & (q_orig["U0"] >= 95)
    for key, mask in screens.items():
        prof, lev = key[0], key[1]
        j = select(mask, prof, Y)
        tag = "audit-then-select, " + lev + (", v >= 1.5 m/s" if len(key) == 3 else "")
        nom = caps[prof] & fast if len(key) == 3 else caps[prof]
        rows.append(row("1 confirmation of reported selection", prof, tag + " (Table 5)", 95.0, lev, j,
                        nom.sum(), mask.sum()))
    mh = caps["hygiene_priority"] & (q_orig["U3"] >= 95) & (r_orig["U3"] <= 0.1)
    rows.append(row("1 confirmation of reported selection", "hygiene_priority",
                    "audit-then-select, U3, with q0.90(Rhyg) <= 0.1 (Table 5)", 99.5, "U3",
                    select(mh, "hygiene_priority", Y), caps["hygiene_priority"].sum(), mh.sum()))

    # ------------------------------------------- 2. conservative audit-then-select
    for lev in ("U0", "U3"):
        q, ql, _ = est[lev]
        conf = np.nan_to_num(ql, nan=-np.inf)
        for prof, m in caps.items():
            for vel in (False, True):
                nom = m & fast if vel else m
                mask = nom & (conf >= 95)
                j = select(mask, prof, Y)
                tag = "conservative audit-then-select, " + lev + (", v >= 1.5 m/s" if vel else "")
                rows.append(row("2 conservative audit-then-select", prof, tag, 95.0, lev, j, nom.sum(),
                                (nom & (q_orig[lev] >= 95)).sum(), mask.sum(), recheck_j=True))
        if lev == "U3":                                           # full profile-specific criterion
            for vel in (False, True):
                nom = caps["hygiene_priority"] & fast if vel else caps["hygiene_priority"]
                mask = nom & (conf >= 99.5)
                j = select(mask, "hygiene_priority", Y)
                tag = "conservative audit-then-select, U3, with q0.90(Rhyg) <= 0.1" + (", v >= 1.5 m/s" if vel else "")
                rows.append(row("2 conservative audit-then-select", "hygiene_priority", tag, 99.5, lev, j,
                                nom.sum(), (nom & (q_orig[lev] >= 99.5)).sum(), mask.sum(), recheck_j=True))

    out = pd.DataFrame(rows)
    out.to_csv(os.path.join(OUT, "conservative_confirmation.csv"), index=False)
    pd.set_option("display.width", 250)
    print(out[["profile", "screening", "n_nominal_feasible", "n_admitted", "n_confirmed", "water_L",
               "total_energy_kWh", "CO2eq_kg", "cleaning_score", "velocity_m_s", "q10_original_M1000",
               "q10_M10000", "q10_M10000_CI95_low", "q10_M10000_CI95_high", "confirmed",
               "q10_recheck_M10000", "q10_recheck_CI95_low", "confirmed_recheck"]].round(3).to_string())
