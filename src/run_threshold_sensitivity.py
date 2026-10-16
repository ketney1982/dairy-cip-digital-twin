# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Sensitivity of robust admissibility to the hygiene floor CS_min and to the
quantile level p, plus nominal vs robust-admissible fronts (water-energy) used in Fig. 6."""
import os
import numpy as np, pandas as pd
from cip_closed_form import simulate, simulate_X, VARS, LB, UB, matlab_rand
from run_robustness_audit import draws, SEED

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "results")

U = matlab_rand(42, 30000, 10)
Xc = LB + U * (UB - LB); Xc[:, 7] = 0.5
Y = simulate_X(Xc)
PS = [0.05, 0.10, 0.20]
Q = {}
for lev in ["U0", "U3"]:
    rng = np.random.default_rng(SEED + 1)
    d = draws(lev, 1000, rng)
    q = np.empty((len(Xc), len(PS)))
    for a in range(0, len(Xc), 500):
        Xb = Xc[a:a + 500]
        y = simulate(Xb[:, [0]] + d["dT"][None, :], Xb[:, [1]] * d["fQ"][None, :], Xb[:, [2]], Xb[:, [3]],
                     Xb[:, [4]], Xb[:, [5]], Xb[:, [6]] * d["fC"][None, :], d["s0"][None, :], Xb[:, [8]], Xb[:, [9]],
                     T_in=d["T_in"][None, :], k_cal=d["k_cal"][None, :], alpha_T=d["alpha_T"][None, :],
                     beta_Q=d["beta_Q"][None, :], gamma=d["gamma"][None, :])
        q[a:a + 500] = np.quantile(y["cleaning_score"], PS, axis=1).T
    Q[lev] = q

rows = []
for lev in ["U0", "U3"]:
    for ip, p in enumerate(PS):
        for cs_min in [90.0, 92.5, 95.0, 97.5, 99.0]:
            nom = Y["cleaning_score"] >= cs_min
            adm = nom & (Q[lev][:, ip] >= cs_min)
            r = dict(uncertainty=lev, quantile=p, CS_min=cs_min, n_nominal=int(nom.sum()), n_admitted=int(adm.sum()),
                     admitted_share_of_nominal=adm.sum() / max(nom.sum(), 1))
            for k in ["water_L", "total_energy_kWh", "CO2eq_kg"]:
                r[f"min_{k}_nominal"] = Y[k][nom].min() if nom.any() else np.nan
                r[f"min_{k}_admitted"] = Y[k][adm].min() if adm.any() else np.nan
            rows.append(r)
tab = pd.DataFrame(rows)
tab.to_csv(os.path.join(OUT, "threshold_quantile_sensitivity.csv"), index=False)
print(tab[(tab["quantile"] == 0.10)].round(2).to_string())


def front(w, e):
    o = np.lexsort((e, w)); best = np.inf; keep = []
    for i in o:
        if e[i] < best:
            keep.append(i); best = e[i]
    return np.array(keep)


fr = []
nom = Y["cleaning_score"] >= 95
for lab, m in [("nominal", nom), ("robust_U0", nom & (Q["U0"][:, 1] >= 95)), ("robust_U3", nom & (Q["U3"][:, 1] >= 95))]:
    idx = np.where(m)[0]
    k = idx[front(Y["water_L"][idx], Y["total_energy_kWh"][idx])]
    for j in k:
        fr.append(dict(set=lab, water_L=Y["water_L"][j], total_energy_kWh=Y["total_energy_kWh"][j],
                       cleaning_score=Y["cleaning_score"][j], q10_U0=Q["U0"][j, 1], q10_U3=Q["U3"][j, 1],
                       **{v: Xc[j, i] for i, v in enumerate(VARS)}))
pd.DataFrame(fr).to_csv(os.path.join(OUT, "water_energy_fronts_nominal_vs_robust.csv"), index=False)
np.savez_compressed(os.path.join(OUT, "candidates_quantiles.npz"), X=Xc, qU0=Q["U0"], qU3=Q["U3"],
                    water=Y["water_L"], energy=Y["total_energy_kWh"], CS=Y["cleaning_score"])
print(pd.DataFrame(fr).groupby("set").size())
