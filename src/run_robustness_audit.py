# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Reconstruct the 30,000-candidate policy envelope (MATLAB rng(42)) and
audit the policy recipes directly on the mechanistic simulator under four
nested uncertainty sets (U0 = initial soil only ... U3 = + kinetic parameters).
"""
import os, json
import numpy as np, pandas as pd
from cip_closed_form import src, simulate, simulate_X, VARS, LB, UB, matlab_rand, P

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")
SEED = 2026

# ---------------------------------------------------------------- uncertainty sets
UNC = {
    "U0": "initial soil load s0 ~ U(0.1, 1.0)",
    "U1": "U0 + operational errors: T ~ N(T_set, 1.5 C); Q, c_NaOH x (1 + N(0, 0.05))",
    "U2": "U1 + inlet-water temperature T_in ~ U(5, 25 C)",
    "U3": "U2 + kinetic-parameter uncertainty: k_cal ~ LN(ln 0.08, 0.25); alpha_T ~ N(0.035, 0.007); beta_Q ~ N(0.45, 0.09); gamma_NaOH ~ N(0.60, 0.12)",
}


def draws(level, M, rng):
    d = dict(s0=rng.uniform(0.1, 1.0, M), dT=np.zeros(M), fQ=np.ones(M), fC=np.ones(M),
             T_in=np.full(M, P["T_in"]), k_cal=np.full(M, P["k_cal"]),
             alpha_T=np.full(M, P["alpha_T"]), beta_Q=np.full(M, P["beta_Q"]),
             gamma=np.full(M, P["gamma_NaOH"]))
    lv = int(level[1])
    if lv >= 1:
        d["dT"] = rng.normal(0, 1.5, M)
        d["fQ"] = 1 + rng.normal(0, 0.05, M)
        d["fC"] = 1 + rng.normal(0, 0.05, M)
    if lv >= 2:
        d["T_in"] = rng.uniform(5, 25, M)
    if lv >= 3:
        d["k_cal"] = np.exp(rng.normal(np.log(P["k_cal"]), 0.25, M))
        d["alpha_T"] = rng.normal(0.035, 0.007, M)
        d["beta_Q"] = rng.normal(0.45, 0.09, M)
        d["gamma"] = rng.normal(0.60, 0.12, M)
    return d


def realised(T_set, Q_set, C_set, d, bounded=False):
    """Realised T, Q and c_NaOH under the setpoint errors of the draws. With
    bounded=True they are truncated to the Table 1 bounds (sensitivity variant:
    the plant cannot run outside the admissible setpoint range)."""
    T, Q, C = T_set + d["dT"], Q_set * d["fQ"], C_set * d["fC"]
    if bounded:
        T, Q, C = np.clip(T, LB[0], UB[0]), np.clip(Q, LB[1], UB[1]), np.clip(C, LB[6], UB[6])
    return T, Q, C


def outside_bounds(T, Q, C):
    return (T < LB[0]) | (T > UB[0]) | (Q < LB[1]) | (Q > UB[1]) | (C < LB[6]) | (C > UB[6])


def mc_eval(x, d, bounded=False):
    """x: recipe vector (10,), d: draws dict -> outputs dict (arrays length M)."""
    T, Q, C = realised(x[0], x[1], x[6], d, bounded)
    return simulate(T, Q, x[2], x[3], x[4], x[5], C, d["s0"],
                    x[8], x[9], T_in=d["T_in"], k_cal=d["k_cal"], alpha_T=d["alpha_T"],
                    beta_Q=d["beta_Q"], gamma=d["gamma"])


def summarise(y, cs_min=95.0):
    return dict(CS_mean=np.mean(y["cleaning_score"]), CS_q10=np.quantile(y["cleaning_score"], 0.10),
                CS_q05=np.quantile(y["cleaning_score"], 0.05),
                P_CS_ge_95=np.mean(y["cleaning_score"] >= cs_min),
                Rhyg_q90=np.quantile(y["hygienic_risk"], 0.90),
                COD_q90=np.quantile(y["COD_mgL"], 0.90),
                water_q90=np.quantile(y["water_L"], 0.90),
                energy_q50=np.quantile(y["total_energy_kWh"], 0.50),
                energy_q90=np.quantile(y["total_energy_kWh"], 0.90),
                CF_q90=np.quantile(y["CO2eq_kg"], 0.90))


if __name__ == "__main__":
    # ------------------------------------------------ reconstruct candidate envelope
    U = matlab_rand(42, 30000, 10)
    Xc = LB + U * (UB - LB)
    Xc[:, 7] = 0.5
    pol = pd.read_csv(src("policy_portfolio_results.csv"))
    rec = {}
    for prof in ["balanced_default", "cod_discharge_limit", "hygiene_priority"]:
        r = pol[pol.profile == prof].iloc[0]
        x = np.array([r[v] for v in VARS], float)
        d = np.max(np.abs((Xc - x) / (UB - LB)), axis=1)
        j = int(np.argmin(d))
        print(f"{prof}: nearest candidate index {j}, max normalised deviation {d[j]:.2e}")
        rec[prof] = Xc[j].copy()            # unrounded recipe
    json.dump({k: dict(zip(VARS, v.tolist())) for k, v in rec.items()},
              open(os.path.join(OUT, "policy_recipes_unrounded.json"), "w"), indent=2)

    # nominal (s0 = 0.5) true-simulator outputs of the three recipes vs surrogate values
    nom_rows = []
    for prof, x in rec.items():
        y = simulate_X(x[None, :])
        r = pol[pol.profile == prof].iloc[0]
        for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "EHPI", "hygienic_risk"]:
            nom_rows.append(dict(profile=prof, output=k, surrogate=r[k], simulator=float(y[k][0])))
    pd.DataFrame(nom_rows).to_csv(os.path.join(OUT, "policy_recipes_nominal_surrogate_vs_simulator.csv"), index=False)

    # --------------------------------------------- MC audit of the selected recipes
    M = 10000
    rows = []
    store = {}
    for lev in UNC:
        rng = np.random.default_rng(SEED)
        d = draws(lev, M, rng)                     # common random numbers across recipes
        for prof, x in rec.items():
            y = mc_eval(x, d)
            s = summarise(y)
            s.update(profile=prof, uncertainty=lev, admitted=bool(s["CS_q10"] >= 95.0))
            # the hygiene-priority profile also has the nominal cap Rhyg <= 0.1;
            # check whether it holds in the upper tail as well (diagnostic only)
            s["policy_Rhyg_cap_met_q90"] = bool(s["Rhyg_q90"] <= 0.1) if prof == "hygiene_priority" else None
            # share of draws whose realised T, Q or c_NaOH leave the Table 1 bounds,
            # and the audit repeated with the realised values truncated to the bounds
            s["frac_draws_outside_bounds"] = float(np.mean(outside_bounds(*realised(x[0], x[1], x[6], d))))
            yb = mc_eval(x, d, bounded=True)
            s["CS_q10_bounded"] = float(np.quantile(yb["cleaning_score"], 0.10))
            s["Rhyg_q90_bounded"] = float(np.quantile(yb["hygienic_risk"], 0.90))
            s["admitted_bounded"] = bool(s["CS_q10_bounded"] >= 95.0)
            rows.append(s)
            store[(prof, lev)] = y["cleaning_score"]
    aud = pd.DataFrame(rows)[["profile", "uncertainty", "CS_mean", "CS_q10", "CS_q05", "P_CS_ge_95",
                              "admitted", "Rhyg_q90", "COD_q90", "water_q90", "energy_q50", "energy_q90", "CF_q90",
                              "policy_Rhyg_cap_met_q90", "frac_draws_outside_bounds", "CS_q10_bounded",
                              "Rhyg_q90_bounded", "admitted_bounded"]]
    aud.to_csv(os.path.join(OUT, "policy_recipes_MC_audit.csv"), index=False)
    print(aud.round(3).to_string())
    np.savez_compressed(os.path.join(OUT, "CS_draws.npz"),
                        **{f"{p}__{l}": v for (p, l), v in store.items()})
    json.dump(UNC, open(os.path.join(OUT, "uncertainty_sets.json"), "w"), indent=2)

    # ------------------- candidate-level audit (all nominally feasible candidates)
    Y = simulate_X(Xc)
    caps = {
        "balanced_default": (Y["cleaning_score"] >= 95),
        "cod_discharge_limit": (Y["cleaning_score"] >= 95) & (Y["COD_mgL"] <= 700),
        "hygiene_priority": (Y["cleaning_score"] >= 98) & (Y["hygienic_risk"] <= 0.1),
    }
    W = {"balanced_default": [0.2222, 0.2222, 0.2222, 0.2222, 0.1112],
         "cod_discharge_limit": [0.1667, 0.1111, 0.4444, 0.1111, 0.1667],
         "hygiene_priority": [0.10, 0.10, 0.15, 0.10, 0.55]}
    w_raw = {"balanced_default": [0.20, 0.20, 0.20, 0.20, 0.10],
             "cod_discharge_limit": [0.15, 0.10, 0.40, 0.10, 0.15],
             "hygiene_priority": [0.10, 0.10, 0.15, 0.10, 0.55]}
    Mc = 1000
    q10, r90, q10b = {}, {}, {}
    for lev in ["U0", "U3"]:
        rng = np.random.default_rng(SEED + 1)
        d = draws(lev, Mc, rng)
        dd = {k: v[None, :] for k, v in d.items()}
        # vectorised over candidates in chunks: (n_cand, Mc)
        q, r, qb = np.empty(len(Xc)), np.empty(len(Xc)), np.empty(len(Xc))
        for a in range(0, len(Xc), 500):
            Xb = Xc[a:a + 500]
            for bounded in (False, True):
                T, Q, C = realised(Xb[:, [0]], Xb[:, [1]], Xb[:, [6]], dd, bounded)
                y = simulate(T, Q, Xb[:, [2]], Xb[:, [3]], Xb[:, [4]], Xb[:, [5]],
                             C, dd["s0"], Xb[:, [8]], Xb[:, [9]],
                             T_in=dd["T_in"], k_cal=dd["k_cal"], alpha_T=dd["alpha_T"],
                             beta_Q=dd["beta_Q"], gamma=dd["gamma"])
                if bounded:
                    qb[a:a + 500] = np.quantile(y["cleaning_score"], 0.10, axis=1)
                else:
                    q[a:a + 500] = np.quantile(y["cleaning_score"], 0.10, axis=1)
                    r[a:a + 500] = np.quantile(y["hygienic_risk"], 0.90, axis=1)
        q10[lev], r90[lev], q10b[lev] = q, r, qb
    np.savez_compressed(os.path.join(OUT, "candidate_q10.npz"), X=Xc, U0=q10["U0"], U3=q10["U3"],
                        Rhyg_q90_U0=r90["U0"], Rhyg_q90_U3=r90["U3"],
                        U0_bounded=q10b["U0"], U3_bounded=q10b["U3"],
                        **{k: Y[k] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]})

    def select(mask, prof, Y=Y):
        idx = np.where(mask)[0]
        if len(idx) == 0:
            return None
        def nz(v):
            v = v[idx]; s = v.max() - v.min(); return (v - v.min()) / (s if s > 0 else 1)
        w = np.array(w_raw[prof]); w = w / w.sum()
        sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
              + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(Y["cleaning_score"])))
        return idx[np.argmin(sc)]

    # screenings: nominal; audit-then-select (U0, U3); the same with the realised
    # setpoints truncated to the Table 1 bounds; and, for hygiene priority, the
    # audit extended to its own cap in the upper tail, q0.90(Rhyg) <= 0.1
    screens = {"nominal": lambda m: m,
               "U0": lambda m: m & (q10["U0"] >= 95), "U3": lambda m: m & (q10["U3"] >= 95),
               "U0_bounded": lambda m: m & (q10b["U0"] >= 95), "U3_bounded": lambda m: m & (q10b["U3"] >= 95),
               "U0_with_Rhyg_cap": lambda m: m & (q10["U0"] >= 95) & (r90["U0"] <= 0.1),
               "U3_with_Rhyg_cap": lambda m: m & (q10["U3"] >= 95) & (r90["U3"] <= 0.1)}
    crow = []
    for prof, m in caps.items():
        for lev, f in screens.items():
            if lev.endswith("Rhyg_cap") and prof != "hygiene_priority":
                continue
            mask = f(m)
            j = select(mask, prof)
            out = dict(profile=prof, screening=lev, n_nominal_feasible=int(m.sum()), n_admitted=int(mask.sum()))
            if j is not None:
                out.update({v: Xc[j, i] for i, v in enumerate(VARS)})
                out.update({k: Y[k][j] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]})
                out.update(q10_U0=q10["U0"][j], q10_U3=q10["U3"][j],
                           Rhyg_q90_U0=r90["U0"][j], Rhyg_q90_U3=r90["U3"][j])
            crow.append(out)

    # minimum-velocity screen (rows appended after the screenings above): mean
    # velocity >= 1.5 m/s in the 22.2-mm internal-diameter tube of Section 2.3,
    # i.e. Q >= 2.09 m3/h, combined with the nominal caps and the audit criterion
    D_TUBE, V_MIN = 0.0222, 1.5
    Q_MIN = V_MIN * np.pi / 4 * D_TUBE ** 2 * 3600.0
    for prof, m in caps.items():
        mv = m & (Xc[:, 1] >= Q_MIN)
        for lev in ["nominal", "U0", "U3"]:
            mask = screens[lev](mv)
            j = select(mask, prof)
            out = dict(profile=prof, screening=lev + "_min_velocity", n_nominal_feasible=int(mv.sum()),
                       n_admitted=int(mask.sum()))
            if j is not None:
                out.update({v: Xc[j, i] for i, v in enumerate(VARS)})
                out.update({k: Y[k][j] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]})
                out.update(q10_U0=q10["U0"][j], q10_U3=q10["U3"][j],
                           Rhyg_q90_U0=r90["U0"][j], Rhyg_q90_U3=r90["U3"][j])
            crow.append(out)
    cand = pd.DataFrame(crow)
    cand["velocity_m_s"] = cand["Q_m3h"] / 3600.0 / (np.pi / 4 * D_TUBE ** 2)
    cand.to_csv(os.path.join(OUT, "candidate_level_admission_and_selection.csv"), index=False)
    print(cand[["profile", "screening", "n_nominal_feasible", "n_admitted", "water_L", "total_energy_kWh",
                "CO2eq_kg", "cleaning_score", "EHPI", "q10_U0", "q10_U3", "velocity_m_s"]].round(3).to_string())

    # ------------- sensitivity to the central value of the kinetic scaling factor
    # k_cal = 0.08 was set a priori (Supplementary Table S1). The candidate-level
    # audit and the policy-recipe audit are repeated with the central value
    # changed by -25% ... +25%; under U3 the log-normal spread (sigma_ln = 0.25)
    # is kept around the new centre, and the policy recipes are held fixed.
    base = pd.read_csv(src("dairy_cip_synthetic_dataset.csv"))
    Xbase = base[VARS].to_numpy(float)
    krows = []
    for kc in [0.06, 0.07, 0.08, 0.09, 0.10]:
        f = kc / P["k_cal"]
        Yk = simulate_X(Xc, k_cal=kc)
        nomk = Yk["cleaning_score"] >= 95
        row = dict(k_cal=kc, base_share_CS_below_95=float(np.mean(simulate_X(Xbase, k_cal=kc)["cleaning_score"] < 95)),
                   n_nominal_feasible=int(nomk.sum()))
        for lev in ["U0", "U3"]:
            d = draws(lev, Mc, np.random.default_rng(SEED + 1))
            d["k_cal"] = d["k_cal"] * f
            dd = {k: v[None, :] for k, v in d.items()}
            qk = np.empty(len(Xc))
            for a in range(0, len(Xc), 500):
                Xb = Xc[a:a + 500]
                T, Q, C = realised(Xb[:, [0]], Xb[:, [1]], Xb[:, [6]], dd)
                y = simulate(T, Q, Xb[:, [2]], Xb[:, [3]], Xb[:, [4]], Xb[:, [5]], C, dd["s0"], Xb[:, [8]],
                             Xb[:, [9]], T_in=dd["T_in"], k_cal=dd["k_cal"], alpha_T=dd["alpha_T"],
                             beta_Q=dd["beta_Q"], gamma=dd["gamma"])
                qk[a:a + 500] = np.quantile(y["cleaning_score"], 0.10, axis=1)
            mask = nomk & (qk >= 95)
            row["n_admitted_" + lev] = int(mask.sum())
            j = select(mask, "balanced_default", Y=Yk)
            row.update({f"bal_{lev}_{k}": float(Yk[k][j]) for k in ["water_L", "total_energy_kWh", "cleaning_score"]})
            row[f"bal_{lev}_Q_m3h"] = float(Xc[j, 1])
            # fixed policy recipes, M = 10,000 common random numbers as in Table 4
            d = draws(lev, M, np.random.default_rng(SEED))
            d["k_cal"] = d["k_cal"] * f
            for prof, x in rec.items():
                row[f"{prof}_CS_q10_{lev}"] = float(np.quantile(mc_eval(x, d)["cleaning_score"], 0.10))
        j = select(nomk, "balanced_default", Y=Yk)
        row.update({f"bal_nominal_{k}": float(Yk[k][j]) for k in ["water_L", "total_energy_kWh", "cleaning_score"]})
        row["bal_nominal_q10_U3"] = float(np.nan)
        for prof, x in rec.items():
            row[f"{prof}_CS_nominal"] = float(simulate_X(x[None, :], k_cal=kc)["cleaning_score"][0])
        krows.append(row)
    ks = pd.DataFrame(krows).drop(columns=["bal_nominal_q10_U3"])
    ks.to_csv(os.path.join(OUT, "kcal_central_sensitivity.csv"), index=False)
    print(ks.round(3).T.to_string())
