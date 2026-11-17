# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E18 - Sensitivity of the illustrative pipe-circuit case to experimentally anchored kinetics (revision R2).

The illustrative case of the manuscript (assumed parameters, E02) is re-audited after replacing its
kinetic assumptions, one group at a time, by the values estimated from published experiments in E16:
  A0  assumptions of the manuscript (alpha_T 0.035, beta_Q 0.45, water rinses 3x / 0.6x the alkaline base rate)
  A1  temperature and flow sensitivities from the experiments (first-order fit: alpha_T, beta_Q)
  A2  water-rinse effectiveness from the experiments (water rate = rho_w x alkaline rate at 70 degC, 0.5 wt% NaOH)
  A3  A1 + A2
  A4  A3 + no rate gain above 0.5 wt% NaOH (rate fixed at its value for 0.5 wt%)
Each variant is run (i) with k_cal = 0.08 and (ii) with k_cal re-centred so that the share of the 5,000
base scenarios below the 95% floor is the same as in the manuscript (the design rationale of k_cal).
Output: ../outputs/E18_anchored_sensitivity.csv
"""
import os
import json
import numpy as np
import pandas as pd
from scipy.optimize import brentq
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
try:                                    # evidence-package layout: cipmodel.py next to this script
    from cipmodel import src, simulate, VARS, LB, UB, matlab_rand, P
except ImportError:                     # repository layout: closed-form simulator in ../../src
    import sys
    sys.path.insert(0, os.path.join(HERE, "..", "..", "src"))
    from cip_closed_form import src, simulate, VARS, LB, UB, matlab_rand, P


def policy_recipes():
    """Unrounded policy recipes: evidence package (outputs/E02_...) or repository (results/policy_recipes_unrounded.json)."""
    for f in (os.path.join(OUT, "E02_policy_recipes_unrounded.json"), os.path.join(HERE, "..", "..", "results", "policy_recipes_unrounded.json")):
        if os.path.exists(f):
            return json.load(open(f))
    raise FileNotFoundError("policy_recipes_unrounded.json")
cal = json.load(open(os.path.join(OUT, "E16_calibrated_rate_law.json")))
ALPHA_X, BETA_X = cal["M1"]["alpha_per_degC"], cal["M1"]["beta"]
RHO_W = cal["water_rinse"]["ratio_first_order"]
SEED, FLOOR = 2026, 95.0
Q_MIN_V15 = 1.5 * np.pi * (0.0222 ** 2) / 4 * 3600.0      # m3/h for 1.5 m/s in the 22.2-mm reference tube


def variant(name):
    v = dict(alpha=P["alpha_T"], beta=P["beta_Q"], gamma=P["gamma_NaOH"], kpb=P["k_pre_base"], krb=P["k_rinse_base"], fix_naoh=False)
    if name in ("A1", "A3", "A4"):
        v.update(alpha=ALPHA_X, beta=BETA_X)
    if name in ("A2", "A3", "A4"):
        kw = RHO_W * P["k_alk_base"] * np.exp(v["alpha"] * (70.0 - P["T_ref"])) * (0.5 / P["NaOH_ref"]) ** v["gamma"]
        v.update(kpb=kw, krb=kw)
    if name == "A4":
        v.update(fix_naoh=True)
    return v


def run(X, v, k_cal, d=None):
    """X: (n, 10) recipes. d: Monte Carlo draws (None = nominal). Returns outputs dict; with draws -> (n, M)."""
    col = (lambda i: X[:, [i]]) if d is not None else (lambda i: X[:, i])
    T, Qf, c, s0 = col(0), col(1), col(6), col(7)
    kw = dict(k_cal=k_cal, alpha_T=v["alpha"], beta_Q=v["beta"], gamma=v["gamma"], k_pre_base=v["kpb"], k_rinse_base=v["krb"])
    if d is not None:
        T = T + d["dT"][None, :]
        Qf = Qf * d["fQ"][None, :]
        c = c * d["fC"][None, :]
        s0 = d["s0"][None, :]
        kw.update(k_cal=k_cal * d["f_kcal"][None, :], alpha_T=v["alpha"] * d["f_alpha"][None, :],
                  beta_Q=v["beta"] * d["f_beta"][None, :], gamma=v["gamma"] * d["f_gamma"][None, :], T_in=d["T_in"][None, :])
    if v["fix_naoh"]:
        c = np.full(np.broadcast(c, T).shape if d is not None else c.shape, 0.5)
    return simulate(T, Qf, col(2), col(3), col(4), col(5), c, s0, col(8), col(9), **kw)


def draws(level, M, rng):
    d = dict(s0=rng.uniform(0.1, 1.0, M), dT=np.zeros(M), fQ=np.ones(M), fC=np.ones(M), T_in=np.full(M, P["T_in"]),
             f_kcal=np.ones(M), f_alpha=np.ones(M), f_beta=np.ones(M), f_gamma=np.ones(M))
    if level >= 1:
        d["dT"], d["fQ"], d["fC"] = rng.normal(0, 1.5, M), 1 + rng.normal(0, 0.05, M), 1 + rng.normal(0, 0.05, M)
    if level >= 2:
        d["T_in"] = rng.uniform(5, 25, M)
    if level >= 3:          # same relative spreads as in the manuscript (sigma_ln 0.25; CV 20%), around the variant's centres
        d["f_kcal"] = np.exp(rng.normal(0, 0.25, M))
        d["f_alpha"], d["f_beta"], d["f_gamma"] = 1 + rng.normal(0, 0.2, M), 1 + rng.normal(0, 0.2, M), 1 + rng.normal(0, 0.2, M)
    return d


def q10(X, v, k_cal, level, M, seed):
    d = draws(level, M, np.random.default_rng(seed))
    out = np.empty(len(X))
    for a in range(0, len(X), 500):
        out[a:a + 500] = np.quantile(run(X[a:a + 500], v, k_cal, d)["cleaning_score"], 0.10, axis=1)
    return out


def select_balanced(Y, mask):
    idx = np.where(mask)[0]
    if len(idx) == 0:
        return None
    nz = lambda a: (a[idx] - a[idx].min()) / max(a[idx].max() - a[idx].min(), 1e-12)
    w = np.array([0.20, 0.20, 0.20, 0.20, 0.10]) / 0.9
    sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"]) + w[3] * nz(Y["CO2eq_kg"])
          + w[4] * (1 - nz(Y["cleaning_score"])))
    return int(idx[np.argmin(sc)])


def main():
    base = pd.read_csv(src("dairy_cip_synthetic_dataset.csv"))
    Xb = base[VARS].to_numpy(float)
    Xc = LB + matlab_rand(42, 30000, 10) * (UB - LB)
    Xc[:, 7] = 0.5
    rec = policy_recipes()
    Xp = np.array([[rec[k][v] for v in VARS] for k in ("balanced_default", "hygiene_priority")])
    share0 = float(np.mean(run(Xb, variant("A0"), P["k_cal"])["cleaning_score"] < FLOOR))
    rows = []
    for name in ("A0", "A1", "A2", "A3", "A4"):
        v = variant(name)
        kc_re = brentq(lambda kc: np.mean(run(Xb, v, kc)["cleaning_score"] < FLOOR) - share0, 0.01, 5.0, xtol=1e-5)
        for mode, kc in (("k_cal = 0.08", P["k_cal"]), ("k_cal re-centred", kc_re)):
            if name == "A0" and mode == "k_cal re-centred":
                continue
            Yb = run(Xb, v, kc)
            pre = 1 - np.exp(-(kc * v["kpb"] * (Xb[:, 1] / P["Q_ref"]) ** v["beta"]) * Xb[:, 2])       # fraction of s0 removed by the pre-rinse
            tot = 1 - Yb["S_end"] / Xb[:, 7]
            Y = run(Xc, v, kc)
            nom = Y["cleaning_score"] >= FLOOR
            q0, q3 = q10(Xc, v, kc, 0, 1000, SEED + 1), q10(Xc, v, kc, 3, 1000, SEED + 1)
            a0, a3 = nom & (q0 >= FLOOR), nom & (q3 >= FLOOR)
            v15 = Xc[:, 1] >= Q_MIN_V15
            pol0, pol3 = q10(Xp, v, kc, 0, 10000, SEED), q10(Xp, v, kc, 3, 10000, SEED)
            polnom = run(np.c_[Xp[:, :7], np.full(2, 0.5), Xp[:, 8:]], v, kc)["cleaning_score"]
            row = dict(variant=name, k_cal_mode=mode, k_cal=kc, alpha_T=v["alpha"], beta_Q=v["beta"],
                       water_to_alkaline_base_ratio=v["kpb"] / P["k_alk_base"], NaOH_effect="none above 0.5 wt%" if v["fix_naoh"] else "power law",
                       share_base_below_floor=float(np.mean(Yb["cleaning_score"] < FLOOR)),
                       median_share_removed_in_prerinse=float(np.median(pre / np.maximum(tot, 1e-12))),
                       nominally_feasible=int(nom.sum()), admitted_U0=int(a0.sum()), admitted_U3=int(a3.sum()),
                       balanced_policy_CS_nom=float(polnom[0]), balanced_policy_q10_U0=float(pol0[0]), balanced_policy_q10_U3=float(pol3[0]),
                       hygiene_policy_CS_nom=float(polnom[1]), hygiene_policy_q10_U0=float(pol0[1]), hygiene_policy_q10_U3=float(pol3[1]))
            for tag, mask in (("nominal", nom), ("ATS_U3", a3), ("nominal_v15", nom & v15), ("ATS_U3_v15", a3 & v15)):
                j = select_balanced(Y, mask)
                if j is None:
                    row.update({f"{tag}_n": 0})
                    continue
                row.update({f"{tag}_n": int(mask.sum()), f"{tag}_water_L": float(Y["water_L"][j]), f"{tag}_energy_kWh": float(Y["total_energy_kWh"][j]),
                            f"{tag}_CS": float(Y["cleaning_score"][j]), f"{tag}_q10_U3": float(q3[j]), f"{tag}_v_m_s": float(Xc[j, 1] / Q_MIN_V15 * 1.5)})
            rows.append(row)
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUT, "E18_anchored_sensitivity.csv"), index=False, float_format="%.5g")
    pd.set_option("display.width", 250)
    print(f"experimental values used: alpha_T = {ALPHA_X:.4f}, beta_Q = {BETA_X:.3f}, water/alkaline(70C, 0.5%) = {RHO_W:.4f}; share below floor (A0) = {share0:.4f}")
    print(df.T.round(3).to_string())


if __name__ == "__main__":
    main()
