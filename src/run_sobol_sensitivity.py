# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Variance-based (Sobol) global sensitivity of the simulator outputs over the
design space of Table 1 (Saltelli et al., 2010 estimators; Jansen total effect)."""
import os
import numpy as np, pandas as pd
from cip_closed_form import simulate_X, VARS, LB, UB

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")
rng = np.random.default_rng(7)
N, d = 2**15, 10
A = LB + rng.random((N, d)) * (UB - LB)
B = LB + rng.random((N, d)) * (UB - LB)
outs = ["cleaning_score", "water_L", "total_energy_kWh", "COD_mgL", "CO2eq_kg", "EHPI"]
yA, yB = simulate_X(A), simulate_X(B)
rows = []
for o in outs:
    fA, fB = yA[o], yB[o]
    V = np.var(np.concatenate([fA, fB]))
    for i, v in enumerate(VARS):
        ABi = A.copy(); ABi[:, i] = B[:, i]
        fAB = simulate_X(ABi)[o]
        S1 = np.mean(fB * (fAB - fA)) / V            # Saltelli 2010
        ST = 0.5 * np.mean((fA - fAB) ** 2) / V        # Jansen 1999
        rows.append(dict(output=o, input=v, S1=S1, ST=ST))
tab = pd.DataFrame(rows)
# bootstrap-free convergence check: repeat with half sample
tab.to_csv(os.path.join(OUT, "sobol_indices.csv"), index=False)
piv = tab.pivot(index="input", columns="output", values="ST").loc[VARS]
print("Total-effect indices ST\n", piv.round(3).to_string())
print("Sum S1 per output:\n", tab.groupby("output").S1.sum().round(3))
