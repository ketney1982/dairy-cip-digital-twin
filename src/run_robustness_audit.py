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


def mc_eval(x, d):
    """x: recipe vector (10,), d: draws dict -> outputs dict (arrays length M)."""
    T = x[0] + d["dT"]
    return simulate(T, x[1] * d["fQ"], x[2], x[3], x[4], x[5], x[6] * d["fC"], d["s0"],
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
            rows.append(s)
            store[(prof, lev)] = y["cleaning_score"]
    aud = pd.DataFrame(rows)[["profile", "uncertainty", "CS_mean", "CS_q10", "CS_q05", "P_CS_ge_95",
                              "admitted", "Rhyg_q90", "COD_q90", "water_q90", "energy_q50", "energy_q90", "CF_q90"]]
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
    q10 = {}
    for lev in ["U0", "U3"]:
        rng = np.random.default_rng(SEED + 1)
        d = draws(lev, Mc, rng)
        # vectorised over candidates in chunks: (n_cand, Mc)
        q = np.empty(len(Xc))
        for a in range(0, len(Xc), 500):
            Xb = Xc[a:a + 500]
            T = Xb[:, [0]] + d["dT"][None, :]
            y = simulate(T, Xb[:, [1]] * d["fQ"][None, :], Xb[:, [2]], Xb[:, [3]], Xb[:, [4]], Xb[:, [5]],
                         Xb[:, [6]] * d["fC"][None, :], d["s0"][None, :], Xb[:, [8]], Xb[:, [9]],
                         T_in=d["T_in"][None, :], k_cal=d["k_cal"][None, :], alpha_T=d["alpha_T"][None, :],
                         beta_Q=d["beta_Q"][None, :], gamma=d["gamma"][None, :])
            q[a:a + 500] = np.quantile(y["cleaning_score"], 0.10, axis=1)
        q10[lev] = q
    np.savez_compressed(os.path.join(OUT, "candidate_q10.npz"), X=Xc, U0=q10["U0"], U3=q10["U3"],
                        **{k: Y[k] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]})

    def select(mask, prof):
        idx = np.where(mask)[0]
        if len(idx) == 0:
            return None
        def nz(v):
            v = v[idx]; s = v.max() - v.min(); return (v - v.min()) / (s if s > 0 else 1)
        w = np.array(w_raw[prof]); w = w / w.sum()
        sc = (w[0] * nz(Y["water_L"]) + w[1] * nz(Y["total_energy_kWh"]) + w[2] * nz(Y["COD_mgL"])
              + w[3] * nz(Y["CO2eq_kg"]) + w[4] * (1 - nz(Y["cleaning_score"])))
        return idx[np.argmin(sc)]

    crow = []
    for prof, m in caps.items():
        for lev in ["nominal", "U0", "U3"]:
            mask = m if lev == "nominal" else (m & (q10[lev] >= 95))
            j = select(mask, prof)
            out = dict(profile=prof, screening=lev, n_nominal_feasible=int(m.sum()), n_admitted=int(mask.sum()))
            if j is not None:
                out.update({v: Xc[j, i] for i, v in enumerate(VARS)})
                out.update({k: Y[k][j] for k in ["water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]})
                out.update(q10_U0=q10["U0"][j], q10_U3=q10["U3"][j])
            crow.append(out)
    cand = pd.DataFrame(crow)
    cand.to_csv(os.path.join(OUT, "candidate_level_admission_and_selection.csv"), index=False)
    print(cand[["profile", "screening", "n_nominal_feasible", "n_admitted", "water_L", "total_energy_kWh",
                "CO2eq_kg", "cleaning_score", "EHPI", "q10_U0", "q10_U3"]].round(3).to_string())
