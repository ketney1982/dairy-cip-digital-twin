# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Benchmarks and checks of the simulator-level robustness audit (revision R1).

Run after src/run_robustness_audit.py (it reads results/candidate_q10.npz).

1. Deterministic benchmarks. Because CS decreases linearly with s0 (Eq. 4a),
   q0.10(CS) under U0 equals the nominal CS at the 90th percentile of the
   soil-load distribution (s0 = 0.91). The candidate audit is compared with
   deterministic design-load checks at s0 = 0.91 and 1.0 and with a
   conservative corner (s0 = 0.91 and k_cal at its 10th percentile under U3).
2. Audit of the gamultiobj Pareto front (results/pareto_solutions.csv) under
   U0 and U3, as in Table 4 (M = 10,000, common random numbers).
3. Monte Carlo stability of the candidate verdicts: the candidate audit is
   repeated with an independent seed at M = 1,000 and at M = 10,000; verdict
   changes are counted, with distribution-free 95% intervals for q0.10.
4. Structural sensitivity: ratio k_pre,base / k_alk,base (nominal 3) and the
   shape of the soil-load distribution (uniform, triangular, beta).
Outputs: results/audit_deterministic_benchmarks.csv, results/pareto_front_audit.csv,
results/mc_threshold_stability.csv, results/structural_sensitivity.csv.
"""
import os
import numpy as np, pandas as pd
from scipy import stats
from cip_closed_form import src, simulate, simulate_X, VARS, LB, UB, matlab_rand, P
from run_robustness_audit import draws, realised, SEED

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")
KEYS = ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]
W_RAW = {"balanced_default": [0.20, 0.20, 0.20, 0.20, 0.10],
         "cod_discharge_limit": [0.15, 0.10, 0.40, 0.10, 0.15],
         "hygiene_priority": [0.10, 0.10, 0.15, 0.10, 0.55]}
D_TUBE = 0.0222
S0_P90 = 0.1 + 0.9 * 0.9                                    # 90th percentile of U(0.1, 1.0)
KCAL_P10 = P["k_cal"] * np.exp(stats.norm.ppf(0.10) * 0.25)  # 10th percentile of k_cal under U3


def velocity(Q):
    return np.asarray(Q) / 3600.0 / (np.pi / 4 * D_TUBE ** 2)


def select(mask, prof, Y):
    """Weighted policy selection of run_robustness_audit.py (min-max normalised)."""
    idx = np.where(mask)[0]
    if len(idx) == 0:
        return None
    def nz(v):
        v = v[idx]; s = v.max() - v.min(); return (v - v.min()) / (s if s > 0 else 1)
    w = np.array(W_RAW[prof]); w = w / w.sum()
    sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
          + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(Y["cleaning_score"])))
    return idx[np.argmin(sc)]


def q10_matrix(X, d, chunk=500, kw=None, quant=0.10):
    """Empirical quantile of CS for every row of X under the draws d."""
    kw = kw or {}
    dd = {k: v[None, :] for k, v in d.items()}
    q = np.empty(len(X))
    for a in range(0, len(X), chunk):
        Xb = X[a:a + chunk]
        T, Q, C = realised(Xb[:, [0]], Xb[:, [1]], Xb[:, [6]], dd)
        y = simulate(T, Q, Xb[:, [2]], Xb[:, [3]], Xb[:, [4]], Xb[:, [5]], C, dd["s0"], Xb[:, [8]], Xb[:, [9]],
                     T_in=dd["T_in"], k_cal=dd["k_cal"], alpha_T=dd["alpha_T"], beta_Q=dd["beta_Q"],
                     gamma=dd["gamma"], **kw)
        q[a:a + chunk] = np.quantile(y["cleaning_score"], quant, axis=1)
    return q


def os_interval(M, p=0.10, level=0.95):
    """Distribution-free (order-statistic) confidence interval ranks for the p-quantile."""
    lo = int(stats.binom.ppf((1 - level) / 2, M, p)); hi = int(stats.binom.ppf(1 - (1 - level) / 2, M, p)) + 1
    return lo, hi           # 1-based ranks


if __name__ == "__main__":
    U = matlab_rand(42, 30000, 10)
    Xc = LB + U * (UB - LB)
    Xc[:, 7] = 0.5
    Y = simulate_X(Xc)
    nom = Y["cleaning_score"] >= 95
    z = np.load(src("candidate_q10.npz"))
    q10U0, q10U3 = z["U0"], z["U3"]
    adm3 = nom & (q10U3 >= 95)

    # ----------------------------------------------- 1. deterministic benchmarks
    def det_cs(s0, k_cal=None):
        X = Xc.copy(); X[:, 7] = s0
        return simulate_X(X, k_cal=k_cal)["cleaning_score"]
    cs091 = det_cs(S0_P90)
    rows = []
    checks = {"U0 audit (M = 1,000)": q10U0, "U3 audit (M = 1,000)": q10U3,
              "deterministic, s0 = 0.91": cs091, "deterministic, s0 = 1.0": det_cs(1.0),
              "deterministic corner, s0 = 0.91 and k_cal = %.4f" % KCAL_P10: det_cs(S0_P90, KCAL_P10)}
    for name, v in checks.items():
        mask = nom & (v >= 95)
        j = select(mask, "balanced_default", Y)
        rows.append(dict(check=name, n_nominal_feasible=int(nom.sum()), n_admitted=int(mask.sum()),
                         n_admitted_and_U3_admitted=int((mask & adm3).sum()),
                         n_admitted_but_U3_rejected=int((mask & ~adm3).sum()),
                         n_rejected_but_U3_admitted=int((~mask & adm3).sum()),
                         sel_index=int(j), sel_water_L=Y["water_L"][j], sel_total_energy_kWh=Y["total_energy_kWh"][j],
                         sel_CO2eq_kg=Y["CO2eq_kg"][j], sel_cleaning_score=Y["cleaning_score"][j],
                         sel_q10_U0=q10U0[j], sel_q10_U3=q10U3[j], sel_velocity_m_s=float(velocity(Xc[j, 1]))))
    det = pd.DataFrame(rows)
    det["corr_with_U0_q10"] = [np.corrcoef(v[nom], q10U0[nom])[0, 1] for v in checks.values()]
    det["max_abs_diff_to_U0_q10"] = [np.max(np.abs(v[nom] - q10U0[nom])) for v in checks.values()]
    det.to_csv(os.path.join(OUT, "audit_deterministic_benchmarks.csv"), index=False)
    print(det.round(4).T.to_string())

    # policy recipes at s0 = 0.91 (equal to their U0 q0.10 of Table 4)
    import json
    rec = json.load(open(src("policy_recipes_unrounded.json")))
    for prof, r in rec.items():
        x = np.array([r[v] for v in VARS], float); x[7] = S0_P90
        print(prof, "CS(s0 = 0.91) =", round(float(simulate_X(x[None, :])["cleaning_score"][0]), 2))

    # ----------------------------------------------- 2. audit of the Pareto front
    par = pd.read_csv(src("pareto_solutions.csv"))
    Xp = par[VARS].to_numpy(float)
    Yp = simulate_X(Xp)
    M = 10000
    pa = par[["selection_label"] + VARS].copy()
    for k in ["water_L", "total_energy_kWh", "CO2eq_kg", "cleaning_score"]:
        pa["surrogate_" + k] = par[k]
        pa["simulator_" + k] = Yp[k]
    for lev in ["U0", "U3"]:
        d = draws(lev, M, np.random.default_rng(SEED))           # same draws as Table 4
        pa["q10_" + lev] = q10_matrix(Xp, d, chunk=20)
        pa["admitted_" + lev] = (pa["simulator_cleaning_score"] >= 95) & (pa["q10_" + lev] >= 95)
    pa["velocity_m_s"] = velocity(pa["Q_m3h"])
    pa.to_csv(os.path.join(OUT, "pareto_front_audit.csv"), index=False)
    print("Pareto front:", len(pa), "recipes; simulator-feasible", int((pa.simulator_cleaning_score >= 95).sum()),
          "; admitted U0", int(pa.admitted_U0.sum()), "; admitted U3", int(pa.admitted_U3.sum()))
    print(pa[pa.selection_label.notna()][["selection_label", "simulator_water_L", "simulator_total_energy_kWh",
                                          "simulator_cleaning_score", "q10_U0", "q10_U3", "admitted_U3"]].round(2).to_string())

    # ----------------------------------------------- 3. Monte Carlo stability
    stab = []
    sel_idx = {}
    for lev, q_orig in (("U0", q10U0), ("U3", q10U3)):
        q_rep = q10_matrix(Xc, draws(lev, 1000, np.random.default_rng(SEED + 101)))
        q_ref = q10_matrix(Xc, draws(lev, 10000, np.random.default_rng(SEED + 202)))
        a_o, a_r, a_ref = nom & (q_orig >= 95), nom & (q_rep >= 95), nom & (q_ref >= 95)
        near = nom & (np.abs(q_orig - 95) < 0.5)
        row = dict(uncertainty=lev, n_nominal_feasible=int(nom.sum()), n_admitted_M1000_seed_original=int(a_o.sum()),
                   n_admitted_M1000_seed_independent=int(a_r.sum()), n_admitted_M10000_seed_independent=int(a_ref.sum()),
                   n_near_threshold_within_0p5=int(near.sum()),
                   n_verdict_changes_M1000_vs_independent_M1000=int((a_o != a_r).sum()),
                   n_verdict_changes_M1000_vs_M10000=int((a_o != a_ref).sum()),
                   verdict_changes_among_near_threshold=int(((a_o != a_ref) & near).sum()),
                   max_abs_q10_change_vs_M10000=float(np.max(np.abs(q_orig[nom] - q_ref[nom]))))
        for prof in ["balanced_default", "cod_discharge_limit"]:
            for tag, a, q in (("original", a_o, q_orig), ("M10000", a_ref, q_ref)):
                j = select(a, prof, Y)
                row[f"{prof}_sel_{tag}_index"] = int(j)
                row[f"{prof}_sel_{tag}_water_L"] = Y["water_L"][j]
                row[f"{prof}_sel_{tag}_total_energy_kWh"] = Y["total_energy_kWh"][j]
                row[f"{prof}_sel_{tag}_q10_M10000"] = q_ref[j]
            sel_idx[(prof, lev)] = row[f"{prof}_sel_original_index"]
        stab.append(row)
    # distribution-free 95% interval of q0.10 (M = 1,000 draws, original seed) for the selected recipes
    lo, hi = os_interval(1000)
    for row in stab:
        lev = row["uncertainty"]
        d = draws(lev, 1000, np.random.default_rng(SEED + 1))
        for prof in ["balanced_default", "cod_discharge_limit"]:
            j = sel_idx[(prof, lev)]
            dd = {k: v for k, v in d.items()}
            T, Q, C = realised(Xc[j, 0], Xc[j, 1], Xc[j, 6], dd)
            cs = np.sort(simulate(T, Q, Xc[j, 2], Xc[j, 3], Xc[j, 4], Xc[j, 5], C, dd["s0"], Xc[j, 8], Xc[j, 9],
                                  T_in=dd["T_in"], k_cal=dd["k_cal"], alpha_T=dd["alpha_T"], beta_Q=dd["beta_Q"],
                                  gamma=dd["gamma"])["cleaning_score"])
            row[f"{prof}_sel_original_q10_CI95_low"] = cs[lo - 1]
            row[f"{prof}_sel_original_q10_CI95_high"] = cs[hi - 1]
    # the same intervals from the independent M = 10,000 audit, for the original and the re-selected recipes
    lo, hi = os_interval(10000)
    for row in stab:
        d = draws(row["uncertainty"], 10000, np.random.default_rng(SEED + 202))
        for prof in ["balanced_default", "cod_discharge_limit"]:
            for tag in ("original", "M10000"):
                j = row[f"{prof}_sel_{tag}_index"]
                T, Q, C = realised(Xc[j, 0], Xc[j, 1], Xc[j, 6], d)
                cs = np.sort(simulate(T, Q, Xc[j, 2], Xc[j, 3], Xc[j, 4], Xc[j, 5], C, d["s0"], Xc[j, 8], Xc[j, 9],
                                      T_in=d["T_in"], k_cal=d["k_cal"], alpha_T=d["alpha_T"], beta_Q=d["beta_Q"],
                                      gamma=d["gamma"])["cleaning_score"])
                row[f"{prof}_sel_{tag}_q10_M10000_CI95_low"] = cs[lo - 1]
                row[f"{prof}_sel_{tag}_q10_M10000_CI95_high"] = cs[hi - 1]
                row[f"{prof}_sel_{tag}_velocity_m_s"] = float(velocity(Xc[j, 1]))
    st = pd.DataFrame(stab)
    st.to_csv(os.path.join(OUT, "mc_threshold_stability.csv"), index=False)
    print(st.round(3).T.to_string())

    # ----------------------------------------------- 4. structural sensitivity
    base = pd.read_csv(src("dairy_cip_synthetic_dataset.csv"))
    Xb = base[VARS].to_numpy(float)
    xs = {p: np.array([r[v] for v in VARS], float) for p, r in rec.items()}
    srows = []

    def audit_case(case, value, kw, s0_sampler=None):
        Yk = simulate_X(Xc, **kw)
        nomk = Yk["cleaning_score"] >= 95
        yb = simulate_X(Xb, **kw)
        kpre = (P["k_cal"] * kw.get("k_pre_base", P["k_pre_base"]) * (Xb[:, 1] / P["Q_ref"]) ** P["beta_Q"]) * Xb[:, 2]
        removed = Xb[:, 7] - yb["S_end"]
        pre_share = np.median(Xb[:, 7] * (1 - np.exp(-kpre)) / removed)
        row = dict(case=case, value=value, base_share_CS_below_95=float(np.mean(yb["cleaning_score"] < 95)),
                   base_median_prerinse_share_of_removal=float(pre_share), n_nominal_feasible=int(nomk.sum()))
        for lev in ["U0", "U3"]:
            d = draws(lev, 1000, np.random.default_rng(SEED + 1))
            if s0_sampler is not None:
                d["s0"] = s0_sampler(np.random.default_rng(SEED + 7), 1000)
            qk = q10_matrix(Xc, d, kw=kw)
            mask = nomk & (qk >= 95)
            j = select(mask, "balanced_default", Yk)
            row.update({f"n_admitted_{lev}": int(mask.sum()), f"bal_{lev}_water_L": Yk["water_L"][j],
                        f"bal_{lev}_total_energy_kWh": Yk["total_energy_kWh"][j], f"bal_{lev}_velocity_m_s": float(velocity(Xc[j, 1]))})
            d = draws(lev, M, np.random.default_rng(SEED))
            if s0_sampler is not None:
                d["s0"] = s0_sampler(np.random.default_rng(SEED + 8), M)
            for prof, x in xs.items():
                row[f"{prof}_CS_q10_{lev}"] = float(q10_matrix(x[None, :], d, chunk=1, kw=kw)[0])
        for prof, x in xs.items():
            row[f"{prof}_CS_nominal"] = float(simulate_X(x[None, :], **kw)["cleaning_score"][0])
        srows.append(row)
        print(case, value, "done")

    for r in [0.5, 1.0, 2.0, 3.0]:
        audit_case("k_pre_base / k_alk_base", r, dict(k_pre_base=r * P["k_alk_base"]))
    audit_case("s0 distribution", "triangular(0.1, 0.5, 1.0)", {},
               lambda g, n: g.triangular(0.1, 0.5, 1.0, n))
    audit_case("s0 distribution", "0.1 + 0.9 Beta(2, 2)", {},
               lambda g, n: 0.1 + 0.9 * g.beta(2, 2, n))
    ss = pd.DataFrame(srows)
    ss.to_csv(os.path.join(OUT, "structural_sensitivity.csv"), index=False)
    print(ss.round(3).T.to_string())
