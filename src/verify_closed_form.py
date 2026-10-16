# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Verify the closed-form simulator against the 5,000 Simulink scenarios
and recover the exact candidate sets used in the original pipeline (MATLAB rng(42))."""
import json, time, os
import numpy as np, pandas as pd
from cip_closed_form import src, simulate_X, VARS, LB, UB, matlab_rand

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")

df = pd.read_csv(src("dairy_cip_synthetic_dataset.csv"))
X = df[VARS].to_numpy()
y = simulate_X(X)
rows = []
for k in ["water_L", "thermal_energy_kWh", "pump_energy_kWh", "total_energy_kWh",
          "COD_mgL", "CO2eq_kg", "cleaning_score", "hygienic_risk", "EHPI"]:
    d = y[k] - df[k].to_numpy()
    rel = np.abs(d) / np.maximum(np.abs(df[k].to_numpy()), 1e-9)
    rows.append(dict(output=k, max_abs_diff=np.max(np.abs(d)), mean_abs_diff=np.mean(np.abs(d)),
                     max_rel_diff=np.max(rel), r2=1 - np.sum(d**2) / np.sum((df[k] - df[k].mean())**2)))
ver = pd.DataFrame(rows)
ver.to_csv(os.path.join(OUT, "closed_form_vs_simulink.csv"), index=False)
print(ver.to_string())

# was the input design generated with MATLAB rng(42), uniform, column-major?
U = matlab_rand(42, 5000, 10)
Xg = LB + U * (UB - LB)
print("max |X_regenerated - X_dataset| =", np.max(np.abs(Xg - X)))

# timing of the closed form
t0 = time.perf_counter(); n = 0
while time.perf_counter() - t0 < 2.0:
    simulate_X(X); n += 1
dt = (time.perf_counter() - t0) / n
print(f"closed form: {dt*1e3:.3f} ms per 5,000 scenarios -> {dt/5000*1e6:.3f} us per scenario")
json.dump(dict(closed_form_s_per_5000=dt, closed_form_us_per_scenario=dt / 5000 * 1e6,
               x_regeneration_max_abs=float(np.max(np.abs(Xg - X)))),
          open(os.path.join(OUT, "timing_closed_form.json"), "w"), indent=2)
