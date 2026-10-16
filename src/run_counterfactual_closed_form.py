# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Re-evaluate the local counterfactual interventions directly on the simulator.

The original study (src/run_counterfactual_cip_study.m) predicted the
intervened recipes with the quantile-regression-forest surrogates. Those
medians are not constrained by the water, energy and soil balances of the
model, so at fixed flow and duration they can, for example, predict a lower
energy demand for a hotter wash. Here the same intervened recipes (setpoints
read from results/counterfactual_cip_results.csv) are evaluated with the
closed-form simulator at s0 = 0.5, and each recipe is audited under U0 and U3
(M = 10,000, common random numbers) with the procedure of run_robustness_audit.py.
"""
import os
import numpy as np, pandas as pd
from cip_closed_form import src, simulate_X, VARS
from run_robustness_audit import draws, mc_eval, SEED

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")
KEYS = ["cleaning_score", "COD_mgL", "water_L", "thermal_energy_kWh", "pump_energy_kWh",
        "total_energy_kWh", "CO2eq_kg", "hygienic_risk", "EHPI"]

cf = pd.read_csv(src("counterfactual_cip_results.csv"))
X = cf[VARS].to_numpy(float)
Y = simulate_X(X)
tab = cf[["intervention", "applied_delta"] + VARS].copy()
for k in KEYS:
    tab[k] = Y[k]
    tab["d_" + k] = Y[k] - Y[k][0]
for k in ["cleaning_score", "water_L", "total_energy_kWh", "CO2eq_kg"]:
    tab["surrogate_d_" + k] = cf["d_" + k]
for k in ["water_L", "total_energy_kWh", "CO2eq_kg"]:
    tab["pct_d_" + k] = 100.0 * tab["d_" + k] / Y[k][0]

M = 10000
for lev in ["U0", "U3"]:
    d = draws(lev, M, np.random.default_rng(SEED))      # same draws for every intervention
    q = [np.quantile(mc_eval(x, d)["cleaning_score"], 0.10) for x in X]
    tab["CS_q10_" + lev] = q
    tab["admitted_" + lev] = np.array(q) >= 95.0

tab.to_csv(os.path.join(OUT, "counterfactual_closed_form.csv"), index=False)
print(tab[["intervention", "cleaning_score", "d_cleaning_score", "d_water_L", "d_total_energy_kWh",
           "d_CO2eq_kg", "pct_d_total_energy_kWh", "CS_q10_U0", "CS_q10_U3"]].round(3).to_string())
