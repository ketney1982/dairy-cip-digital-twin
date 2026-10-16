# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Local counterfactual interventions evaluated directly on the simulator.

The original study (src/run_counterfactual_cip_study.m) predicted intervened
recipes with the quantile-regression-forest surrogates, around a baseline taken
from the exploratory AI-supervisory layer (results/ai_supervisory_recommendation.json).
Those surrogate medians are not constrained by the water, energy and soil
balances of the model, and that baseline is not a recipe of the main text; both
are kept in results/counterfactual_cip_results.csv for traceability only.

Here the baseline is the balanced-default policy recipe of main Table 3
(results/policy_recipes_unrounded.json, produced by run_robustness_audit.py).
Each intervention changes one or two setpoints (clamped to the Table 1 bounds);
the intervened recipes are evaluated with the closed-form simulator at s0 = 0.5
and audited under U0 and U3 (M = 10,000, common random numbers) with the
procedure of run_robustness_audit.py.
"""
import os, json
import numpy as np, pandas as pd
from cip_closed_form import src, simulate_X, VARS, LB, UB
from run_robustness_audit import draws, mc_eval, SEED

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")
KEYS = ["cleaning_score", "COD_mgL", "water_L", "thermal_energy_kWh", "pump_energy_kWh",
        "total_energy_kWh", "CO2eq_kg", "hygienic_risk", "EHPI"]

base = json.load(open(src("policy_recipes_unrounded.json")))["balanced_default"]
x0 = np.array([base[v] for v in VARS], float)
IV = VARS.index
# (label, [(variable, kind, amount)]); kind "rel" = relative change, "abs" = absolute change
INTERVENTIONS = [
    ("baseline", []),
    ("t_alk_-10%", [("t_alk", "rel", -0.10)]),
    ("t_alk_-20%", [("t_alk", "rel", -0.20)]),
    ("t_alk_+20%", [("t_alk", "rel", +0.20)]),
    ("T_C_-5C", [("T_C", "abs", -5.0)]),
    ("T_C_+2C", [("T_C", "abs", +2.0)]),
    ("Q_m3h_+20%", [("Q_m3h", "rel", +0.20)]),
    ("NaOH_pct_-20%", [("NaOH_pct", "rel", -0.20)]),
    ("water_rec_+0.15", [("water_rec", "abs", +0.15)]),
    ("T_C_-5C_&_t_alk_+20%", [("T_C", "abs", -5.0), ("t_alk", "rel", +0.20)]),
]

rows, X = [], []
for label, changes in INTERVENTIONS:
    x = x0.copy(); applied = []
    for v, kind, a in changes:
        i = IV(v)
        new = x[i] * (1 + a) if kind == "rel" else x[i] + a
        new = float(np.clip(new, LB[i], UB[i]))
        applied.append(f"{v}: {x[i]:.4g} -> {new:.4g} ({new - x[i]:+.4g})")
        x[i] = new
    X.append(x)
    rows.append(dict(intervention=label, applied_delta="; ".join(applied) or "(baseline)"))
X = np.array(X)
Y = simulate_X(X)
tab = pd.DataFrame(rows)
for i, v in enumerate(VARS):
    tab[v] = X[:, i]
for k in KEYS:
    tab[k] = Y[k]
    tab["d_" + k] = Y[k] - Y[k][0]
for k in ["water_L", "total_energy_kWh", "CO2eq_kg"]:
    tab["pct_d_" + k] = 100.0 * tab["d_" + k] / Y[k][0]
tab["nominally_feasible"] = tab["cleaning_score"] >= 95.0

M = 10000
for lev in ["U0", "U3"]:
    d = draws(lev, M, np.random.default_rng(SEED))      # same draws for every intervention
    q = [np.quantile(mc_eval(x, d)["cleaning_score"], 0.10) for x in X]
    tab["CS_q10_" + lev] = q
    tab["admitted_" + lev] = tab["nominally_feasible"] & (np.array(q) >= 95.0)

tab.to_csv(os.path.join(OUT, "counterfactual_closed_form.csv"), index=False)
print(tab[["intervention", "applied_delta", "cleaning_score", "d_cleaning_score", "d_water_L", "pct_d_water_L",
           "d_total_energy_kWh", "pct_d_total_energy_kWh", "d_CO2eq_kg", "d_COD_mgL", "CS_q10_U0", "CS_q10_U3"]].round(3).to_string())
