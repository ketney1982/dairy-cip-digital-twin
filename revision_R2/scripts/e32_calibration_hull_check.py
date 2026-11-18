# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E32 - Calibrated case: audit restricted to the temperature-velocity combinations covered by the calibration curves.

The eight calibration curves cover six velocities at 70 degC and two further temperatures (60 and 50 degC) at one
velocity (1 cm/s). The candidate domain of E17 is the rectangle 50-70 degC x 0.5-23 cm/s, most of which contains no
measured combination of temperature and velocity. Here the nominal setpoints are restricted to the convex hull of the
eight calibration conditions in the plane (T, ln v), and the nominal screening, the non-dominated set and the audit
under U3 are repeated on the candidates inside the hull (variant V4, to be read with variants V0-V3 of E26).

The candidates and their audit results are those of E17 (same candidates, same draws); only the two selected recipes
are re-audited with an independent sample (M = 10,000), as in E17 and E26. The restriction concerns the nominal
setpoints: the realised temperature and velocity of a cycle are still drawn around them (variants V1 and V3 of E26
treat the realised values).

Input:  ../outputs/E17_candidates.csv (written by e17; not stored in the repository - run e17 first),
        ../outputs/E16_per_curve_fits.csv
Output: ../outputs/E32_calibration_hull_counts.csv, E32_calibration_hull_selected.csv
"""
import os
import sys
import importlib.util
import numpy as np
import pandas as pd
from scipy.spatial import ConvexHull

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")


def load(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fn))
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


e17 = load("e17_calibrated_case_audit", "e17_calibrated_case_audit.py")
FLOOR, Q, MODEL = e17.FLOOR, e17.Q, "M0"
TLO, THI, VLO, VHI = 50.0, 70.0, 0.5, 23.0


def calibration_hull():
    per = pd.read_csv(os.path.join(OUT, "E16_per_curve_fits.csv"))
    cond = per[per.role == "calibration"][["T_C", "v_cm_s"]].drop_duplicates().sort_values(["T_C", "v_cm_s"])
    pts = np.column_stack([cond.T_C.to_numpy(float), np.log(cond.v_cm_s.to_numpy(float))])
    return cond, ConvexHull(pts)


def in_hull(hull, T, v, tol=1e-9):
    x = np.column_stack([T, np.log(v)])
    return np.all(x @ hull.equations[:, :2].T + hull.equations[:, 2] <= tol, axis=1)


def main():
    res = pd.read_csv(os.path.join(OUT, "E17_candidates.csv"))
    T, v, t = res.T_C.to_numpy(), res.v_cm_s.to_numpy(), res.t_min.to_numpy()
    V, E = res.V_L.to_numpy(), res.E_kWh.to_numpy()
    q0, q3, low3 = res[f"q10_U0_{MODEL}"].to_numpy(), res[f"q10_U3_{MODEL}"].to_numpy(), res[f"q10low_U3_{MODEL}"].to_numpy()
    nom = res[f"CS_nom_{MODEL}"].to_numpy() >= FLOOR
    cond, hull = calibration_hull()
    inside = in_hull(hull, T, v)
    F = np.column_stack([V, E, t])
    rows, sels = [], []
    for name, mask in (("V0 unrestricted", np.ones(len(T), bool)),
                       ("V4 setpoints inside the convex hull of the calibration conditions", inside)):
        nm = nom & mask
        idx = np.where(nm)[0]
        front = idx[e17.nondominated(F[idx])]
        adm, conf = nm & (q3 >= FLOOR), nm & (low3 >= FLOOR)
        rows.append(dict(variant=name, candidates=int(mask.sum()), candidates_excluded=int((~mask).sum()),
                         nominally_feasible=int(nm.sum()), admitted_U0_point_estimate=int((nm & (q0 >= FLOOR)).sum()),
                         admitted_U3_point_estimate=int(adm.sum()), admitted_U3_confirmed_lower_limit=int(conf.sum()),
                         nominal_front_size=len(front), front_admitted_U0=int((q0[front] >= FLOOR).sum()),
                         front_admitted_U3=int((q3[front] >= FLOOR).sum()), front_q10_U3_min=float(q3[front].min()),
                         front_q10_U3_median=float(np.median(q3[front])), front_q10_U3_max=float(q3[front].max())))
        for scr, m_ in (("nominal", nm), ("audit-then-select U3", conf)):
            sub = np.where(m_)[0]
            for sel, i in (("minimum volume", sub[np.argmin(V[sub])]), ("minimum time", sub[np.argmin(t[sub])])):
                dd = e17.draws(MODEL, e17.M_POLICY, 3, np.random.default_rng(903))       # independent sample, as in E17 / E26
                Tm, vm = T[i] + dd["dT"], np.maximum(v[i] * dd["fv"], 1e-6)
                c = e17.cs(e17.h_end(MODEL, Tm, vm, t[i], dd["h0"], dd["p"], dd["eps"]))
                kk = int(np.floor(e17.M_POLICY * Q - 1.96 * np.sqrt(e17.M_POLICY * Q * (1 - Q))))
                sels.append(dict(variant=name, screening=scr, selection=sel, T_C=T[i], v_cm_s=v[i], t_min=t[i], V_L=V[i], E_kWh=E[i],
                                 q10_U3=float(np.quantile(c, Q)), q10_U3_lower95=float(np.sort(c)[kk]),
                                 P_CS_ge_floor=float(np.mean(c >= FLOOR)),
                                 share_draws_outside_rectangle=float(np.mean((Tm > THI) | (Tm < TLO) | (vm < VLO) | (vm > VHI))),
                                 share_draws_outside_hull=float(np.mean(~in_hull(hull, Tm, vm)))))
    rows, sels = pd.DataFrame(rows), pd.DataFrame(sels)
    rows.to_csv(os.path.join(OUT, "E32_calibration_hull_counts.csv"), index=False, float_format="%.5g")
    sels.to_csv(os.path.join(OUT, "E32_calibration_hull_selected.csv"), index=False, float_format="%.5g")
    with pd.option_context("display.width", 250, "display.max_columns", 30):
        print("calibration conditions (T, v):", [tuple(r) for r in cond.to_numpy()])
        print("hull vertices (T, v):", [(float(a), float(np.exp(b))) for a, b in hull.points[hull.vertices]])
        print(rows.T.to_string()); print(sels.round(3).to_string(index=False))


if __name__ == "__main__":
    main()
