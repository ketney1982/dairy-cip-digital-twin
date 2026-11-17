# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E28 - Checks added in the third revision (R2.2).

A. Retrospective check: cleaning score read at the LAST measured point of every curve for which the audited (U3)
   wash time lies after that point (E26_C status "after last measured point").
B. Illustrative pipe-circuit case re-audited with a uniform-removal (zero-order) law in place of the first-order law,
   i.e. the same Pareto-Monte Carlo procedure with a second kinetic structure. The uniform law removes soil at a constant
   rate r = c * k per phase (k = first-order rate constant of the phase), with c = 0.9*0.5/ln(10) = 0.195, so that both laws
   need the same time to remove 90% of the nominal load s0 = 0.5. Its closed form is S_end = max(s0 - c*sum_i k_i t_i, 0).
Outputs: ../outputs/E28_A_last_point_check.csv, E28_B_uniform_law_pipe_circuit.csv
"""
import os, sys, importlib.util
import numpy as np
import pandas as pd
from scipy.optimize import brentq
HERE = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(HERE, "..", "outputs")
spec = importlib.util.spec_from_file_location("e18", os.path.join(HERE, "e18_anchored_sensitivity_illustrative_case.py"))
e18 = importlib.util.module_from_spec(spec); spec.loader.exec_module(e18)
P, VARS, LB, UB, matlab_rand, src = e18.P, e18.VARS, e18.LB, e18.UB, e18.matlab_rand, e18.src
FLOOR, SEED, H_REF = 95.0, 2026, 3.0
C_UNI = 0.9 * 0.5 / np.log(10.0)


def part_A():
    cv = pd.read_csv(os.path.join(OUT, "E26_C_retrospective_status.csv"))
    per = pd.read_csv(os.path.join(OUT, "E16_per_curve_fits.csv")).set_index("curve")
    obs = pd.read_csv(os.path.join(OUT, "E16_observed_vs_predicted.csv")); obs = obs[obs.model == "M0"]
    rows = []
    for _, r in cv[cv.status == "after last measured point"].iterrows():
        g = obs[obs.curve == r.curve].sort_values("t_min"); h0 = per.loc[r.curve, "h0_mm"]
        cs = lambda y: 100.0 * (1.0 - y * h0 / H_REF)
        rows.append(dict(curve=r.curve, wash_time_rule=r.wash_time_rule, wash_time_min=r.wash_time_min, t_end_obs_min=r.t_end_obs_min,
                         CS_last_point=cs(g.y_obs.iloc[-1]), CS_mean_last3=cs(g.y_obs.iloc[-3:].mean()),
                         last_point_at_or_above_floor=bool(cs(g.y_obs.iloc[-1]) >= FLOOR),
                         last3_mean_at_or_above_floor=bool(cs(g.y_obs.iloc[-3:].mean()) >= FLOOR)))
    df = pd.DataFrame(rows); df.to_csv(os.path.join(OUT, "E28_A_last_point_check.csv"), index=False, float_format="%.5g")
    return df


def run_u(X, v, k_cal, d=None):
    Y = e18.run(X, v, k_cal, d)
    s0 = (d["s0"][None, :] if d is not None else X[:, 7])
    S = np.maximum(s0 - C_UNI * Y["exponent"], 0.0)
    Y = dict(Y); Y["S_end"] = S; Y["cleaning_score"] = np.clip(100.0 * (1.0 - S), 0, 100)
    Y["COD_mgL"] = P["COD_factor"] * np.maximum(s0 - S, 0.0)
    return Y


def q10_u(X, v, k_cal, level, M, seed):
    d = e18.draws(level, M, np.random.default_rng(seed)); out = np.empty(len(X))
    for a in range(0, len(X), 500):
        out[a:a + 500] = np.quantile(run_u(X[a:a + 500], v, k_cal, d)["cleaning_score"], 0.10, axis=1)
    return out


def part_B():
    base = pd.read_csv(src("dairy_cip_synthetic_dataset.csv")); Xb = base[VARS].to_numpy(float)
    Xc = LB + matlab_rand(42, 30000, 10) * (UB - LB); Xc[:, 7] = 0.5
    rec = e18.policy_recipes()
    Xp = np.array([[rec[k][v] for v in VARS] for k in ("balanced_default", "hygiene_priority")])
    share0 = float(np.mean(e18.run(Xb, e18.variant("A0"), P["k_cal"])["cleaning_score"] < FLOOR))
    rows = []
    for name in ("A0", "A3"):
        v = e18.variant(name)
        for law, runf, q10f in (("first-order", e18.run, e18.q10), ("uniform removal", run_u, q10_u)):
            kc_re = brentq(lambda kc: np.mean(runf(Xb, v, kc)["cleaning_score"] < FLOOR) - share0, 0.01, 20.0, xtol=1e-5)
            modes = (("k_cal = 0.08", P["k_cal"]),) if name == "A0" else ()
            modes += (("k_cal re-centred", kc_re),)
            if name == "A0" and law == "first-order":
                modes = (("k_cal = 0.08", P["k_cal"]),)
            for mode, kc in modes:
                Y = runf(Xc, v, kc); nom = Y["cleaning_score"] >= FLOOR
                q0, q3 = q10f(Xc, v, kc, 0, 1000, SEED + 1), q10f(Xc, v, kc, 3, 1000, SEED + 1)
                a0, a3 = nom & (q0 >= FLOOR), nom & (q3 >= FLOOR)
                pol3 = q10f(Xp, v, kc, 3, 10000, SEED); pol0 = q10f(Xp, v, kc, 0, 10000, SEED)
                Yb = runf(Xb, v, kc)
                row = dict(parameterisation=name, law=law, k_cal_mode=mode, k_cal=kc, share_base_below_floor=float(np.mean(Yb["cleaning_score"] < FLOOR)),
                           nominally_feasible=int(nom.sum()), admitted_U0=int(a0.sum()), admitted_U3=int(a3.sum()),
                           balanced_q10_U0=float(pol0[0]), balanced_q10_U3=float(pol3[0]),
                           cleaning_priority_q10_U0=float(pol0[1]), cleaning_priority_q10_U3=float(pol3[1]))
                polnom = runf(np.c_[Xp[:, :7], np.full(2, 0.5), Xp[:, 8:]], v, kc)["cleaning_score"]
                row.update(balanced_CS_nom=float(polnom[0]), cleaning_priority_CS_nom=float(polnom[1]))
                v15 = Xc[:, 1] >= e18.Q_MIN_V15
                for tag, mask in (("nominal", nom), ("ATS_U3", a3), ("ATS_U3_v15", a3 & v15)):
                    j = e18.select_balanced(Y, mask)
                    row.update({f"{tag}_n": int(mask.sum()), f"{tag}_water_L": float(Y["water_L"][j]), f"{tag}_energy_kWh": float(Y["total_energy_kWh"][j]),
                                f"{tag}_CS": float(Y["cleaning_score"][j]), f"{tag}_q10_U3": float(q3[j]),
                                f"{tag}_v_m_s": float(Xc[j, 1] / e18.Q_MIN_V15 * 1.5)})
                row["ATS_over_nominal_water"] = row["ATS_U3_water_L"] / row["nominal_water_L"]
                row["ATS_over_nominal_energy"] = row["ATS_U3_energy_kWh"] / row["nominal_energy_kWh"]
                rows.append(row)
    df = pd.DataFrame(rows); df.to_csv(os.path.join(OUT, "E28_B_uniform_law_pipe_circuit.csv"), index=False, float_format="%.5g")
    return df


if __name__ == "__main__":
    pd.set_option("display.width", 250); pd.set_option("display.max_columns", 60)
    a = part_A()
    for rule, g in a.groupby("wash_time_rule"):
        print(rule, len(g), "last point >= floor:", int(g.last_point_at_or_above_floor.sum()), "mean of last 3 >= floor:", int(g.last3_mean_at_or_above_floor.sum()),
              "min CS last point: %.1f" % g.CS_last_point.min())
    print(part_B().T.round(3).to_string())
