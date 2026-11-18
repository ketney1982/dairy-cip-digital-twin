# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E37 - Does the choice of the uniform-removal law decide the verdicts of the audit? (revision R2)

The two-stage law (M2) fitted the measured curves best (E16), but it was not used in the audit of the calibrated case.
This script (1) reports how stable the two-stage parameters are across the eight calibration curves, and (2) repeats
the audit of the calibrated case (E17) with a lumped two-stage law in which the transition and the rate ratio are fixed:

  removal at rate r(T, v) until a fraction phi of the initial thickness h0 has been removed, then at rate rho * r:
      h(t) = h0 - r t                                   for r t <= phi h0
      h(t) = max(h0 [1 + phi (rho - 1)] - rho r t, 0)   afterwards
  r(T, v) = r_ref exp[alpha (T - 70)] (v / 1 cm/s)^beta  (as Eq. 7 of the manuscript)

phi and rho are set to the medians of the curve-by-curve fits (variant A: eight calibration curves; variant B: eleven
thickness curves); r_ref, alpha and beta are calibrated on the eight calibration curves as in E16 (least squares,
equal weight per curve, jackknife covariance, leave-one-condition-out), and the prediction-error factor of U3 is
derived in the same way as for the other laws. The candidates, draws, uncertainty sets and criteria are those of E17.
Output: ../outputs/E37_two_stage_audit.csv, E37_two_stage_parameter_spread.csv, E37_summary.json
"""
import importlib.util
import json
import os

import numpy as np
import pandas as pd
from scipy.optimize import least_squares

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")


def _load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


e16 = _load("e16", "e16_experimental_benchmark.py")
e17 = _load("e17", "e17_calibrated_case_audit.py")
LAW = dict(phi=0.5, rho=3.0)                      # set per variant in main()
_h_end_e17 = e17.h_end


def y_m2(t, T, v, h0, p, eps=1.0):
    """Normalised residual thickness h/h0 of the lumped two-stage law."""
    r = e16.rate(T, v, p) * eps if np.ndim(p) == 1 else e17.rate(T, v, p) * eps
    x = r * np.asarray(t) / h0                      # thickness removed at the first-stage rate, as a fraction of h0
    phi, rho = LAW["phi"], LAW["rho"]
    return np.where(x <= phi, 1.0 - x, np.maximum(1.0 + phi * (rho - 1.0) - rho * x, 0.0))


def h_end(model, T, v, t, h0, p, eps=1.0):
    if model != "M2":
        return _h_end_e17(model, T, v, t, h0, p, eps)
    r = e17.rate(T, v, p) * eps
    phi, rho = LAW["phi"], LAW["rho"]
    return np.where(r * t <= phi * h0, h0 - r * t, np.maximum(h0 * (1.0 + phi * (rho - 1.0)) - rho * r * t, 0.0))


e17.h_end = h_end                                    # e17.audit / wash_time then evaluate M2 as well


def t90_m2(T, v, h0, p):
    r = e16.rate(T, v, p)
    phi, rho = LAW["phi"], LAW["rho"]
    return 0.9 * h0 / r if phi >= 0.9 else h0 * (0.9 + phi * (rho - 1.0)) / (rho * r)


def calibrate(cs):
    def resid(p):
        return np.concatenate([(y_m2(c["t"], c["T"], c["v"], c["h0"], p) - c["y"]) / np.sqrt(len(c["y"])) for c in cs])
    return least_squares(resid, [0.15, 0.06, 0.4], bounds=([1e-4, 0.0, 0.0], [5.0, 0.3, 2.0])).x


def main():
    curves = e16.load_curves()
    for c in curves:
        c["role"] = e16.role(c)
    cal = [c for c in curves if c["role"] == "calibration"]
    val = [c for c in curves if c["role"].startswith("validation") and "independent" not in c["role"]]

    # ---- 1. spread of the two-stage parameters fitted curve by curve
    per = pd.read_csv(os.path.join(OUT, "E16_per_curve_fits.csv"))
    per = per[per.role != "duplicate"].copy()
    per["phi"] = per.M2_r1 * per.M2_tau_min          # fraction of the layer removed at the transition
    spread = per[["curve", "role", "kind", "T_C", "v_cm_s", "phi", "M2_rate_ratio", "M0_rmse", "M2_rmse"]]
    spread.to_csv(os.path.join(OUT, "E37_two_stage_parameter_spread.csv"), index=False, float_format="%.4g")
    pc = per[per.role == "calibration"]
    pt = per[per.kind == "thickness"]
    summary = dict(calibration_curves=dict(phi_min=float(pc.phi.min()), phi_max=float(pc.phi.max()), phi_median=float(pc.phi.median()),
                                           rho_min=float(pc.M2_rate_ratio.min()), rho_max=float(pc.M2_rate_ratio.max()),
                                           rho_median=float(pc.M2_rate_ratio.median()),
                                           n_second_stage_slower=int((pc.M2_rate_ratio < 1).sum()), n=int(len(pc))),
                   thickness_curves=dict(phi_median=float(pt.phi.median()), rho_median=float(pt.M2_rate_ratio.median()), n=int(len(pt))))
    variants = dict(A=(float(pc.phi.median()), float(pc.M2_rate_ratio.median())),
                    B=(float(pt.phi.median()), float(pt.M2_rate_ratio.median())))

    # ---- 2. candidates of E17 (same seed) and the uniform-law reference
    rng = np.random.default_rng(42)
    u = rng.random((e17.N_CAND, 3))
    T = e17.LB["T"] + u[:, 0] * (e17.UB["T"] - e17.LB["T"])
    v = np.exp(np.log(e17.LB["v"]) + u[:, 1] * (np.log(e17.UB["v"]) - np.log(e17.LB["v"])))
    t = e17.LB["t"] + u[:, 2] * (e17.UB["t"] - e17.LB["t"])
    V, E = e17.burdens(T, v, t)
    F = np.column_stack([V, E, t])
    retro_curves = [c for c in curves if c["role"] != "duplicate" and "independent" not in c["role"]]

    rows = []
    for name, (phi, rho) in variants.items():
        LAW.update(phi=phi, rho=rho)
        p = calibrate(cal)
        jk = np.array([calibrate([c for c in cal if c is not d]) for d in cal])
        n = len(cal)
        lj = np.column_stack([np.log(jk[:, 0]), jk[:, 1], jk[:, 2]])
        cov = (n - 1) / n * (lj - lj.mean(axis=0)).T @ (lj - lj.mean(axis=0))

        def ratio(c, pp):
            return t90_m2(c["T"], c["v"], c["h0"], pp) / e16.t_cross(c["t"], c["y"], 0.10)
        r_loco = np.array([ratio(d, pj) for d, pj in zip(cal, jk)])
        r_val = np.array([ratio(c, p) for c in val])
        sig = float(np.sqrt(0.5 * (np.std(np.log(r_loco), ddof=1) ** 2 + np.std(np.log(r_val), ddof=1) ** 2)))
        rmse_cal = float(np.sqrt(np.mean([np.mean((y_m2(c["t"], c["T"], c["v"], c["h0"], p) - c["y"]) ** 2) for c in cal])))
        rmse_val = float(np.sqrt(np.mean([np.mean((y_m2(c["t"], c["T"], c["v"], c["h0"], p) - c["y"]) ** 2) for c in val])))

        cs_nom = e17.cs(h_end("M2", T, v, t, e17.H_NOM, p))
        nom = cs_nom >= e17.FLOOR
        q = {}
        for level in (0, 3):
            d = e17.draws("M2", e17.M_CAND, level, np.random.default_rng(100 + level), p=p, cov=cov, sigma=sig)
            q[level] = e17.audit("M2", T, v, t, d)
        idx = np.where(nom)[0]
        front = idx[e17.nondominated(F[idx])]
        a3 = nom & (q[3][0] >= e17.FLOOR)
        c3 = nom & (q[3][1] >= e17.FLOOR)
        # minimum-volume recipes: nominal and audit-then-select under U3, confirmed with an independent sample
        sel = {}
        for lab, mask in (("nominal", nom), ("U3", c3)):
            i = int(np.where(mask)[0][np.argmin(V[mask])])
            d = e17.draws("M2", e17.M_POLICY, 3, np.random.default_rng(903), p=p, cov=cov, sigma=sig)
            c = e17.cs(h_end("M2", T[i] + d["dT"], np.maximum(v[i] * d["fv"], 1e-6), t[i], d["h0"], d["p"], d["eps"]))
            sel[lab] = dict(T_C=float(T[i]), v_cm_s=float(v[i]), t_min=float(t[i]), V_L=float(V[i]), q10_U3=float(np.quantile(c, e17.Q)))
        # wash times at the conditions of the 16 curves (full calibration) and their reading in the measured curves
        retro = []
        for (Tc, vc) in sorted({(c["T"], c["v"]) for c in retro_curves}):
            tw = dict(nominal=e17.wash_time("M2", Tc, vc, p),
                      U0=e17.wash_time("M2", Tc, vc, p, e17.draws("M2", e17.M_POLICY, 0, np.random.default_rng(900), p=p, cov=cov, sigma=sig)),
                      U3=e17.wash_time("M2", Tc, vc, p, e17.draws("M2", e17.M_POLICY, 3, np.random.default_rng(903), p=p, cov=cov, sigma=sig)))
            for c in [c for c in retro_curves if (c["T"], c["v"]) == (Tc, vc)]:
                for lab, w in tw.items():
                    retro.append(dict(curve=c["id"], T_C=Tc, v_cm_s=vc, wash_time_rule=lab, wash_time_min=w,
                                      **e17.read_curve(w, c["t"], c["y"], c["h0"])))
        retro = pd.DataFrame(retro)
        rs = e17.retro_summary(retro.assign(model="M2"), ["model", "wash_time_rule"])
        g = retro[(retro.T_C == 70) & np.isclose(retro.v_cm_s, 1.0)].groupby("wash_time_rule").wash_time_min.first()
        rows.append(dict(
            variant=name, phi=phi, rho=rho, r_ref=float(p[0]), alpha=float(p[1]), beta=float(p[2]),
            se_r_ref=float(np.sqrt((n - 1) / n * ((jk[:, 0] - jk[:, 0].mean()) ** 2).sum())),
            se_alpha=float(np.sqrt((n - 1) / n * ((jk[:, 1] - jk[:, 1].mean()) ** 2).sum())),
            se_beta=float(np.sqrt((n - 1) / n * ((jk[:, 2] - jk[:, 2].mean()) ** 2).sum())),
            rmse_calibration=rmse_cal, rmse_validation=rmse_val,
            t90_ratio_loco_min=float(r_loco.min()), t90_ratio_loco_max=float(r_loco.max()),
            t90_ratio_val_min=float(r_val.min()), t90_ratio_val_max=float(r_val.max()), t90_ratio_val_median=float(np.median(r_val)),
            sigma_prediction_error=sig,
            nominally_feasible=int(nom.sum()), admitted_U0=int((nom & (q[0][0] >= e17.FLOOR)).sum()), admitted_U3=int(a3.sum()),
            confirmed_U3=int(c3.sum()), front_size=int(len(front)),
            front_admitted_U0=int((q[0][0][front] >= e17.FLOOR).sum()), front_admitted_U3=int((q[3][0][front] >= e17.FLOOR).sum()),
            front_q10_U3_min=float(q[3][0][front].min()), front_q10_U3_max=float(q[3][0][front].max()),
            nominal_min_volume=sel["nominal"], U3_min_volume=sel["U3"],
            t_70C_1cms=dict(g), U3_over_nominal_70C_1cms=float(g["U3"] / g["nominal"]),
            retrospective_full_calibration=e17.records(rs)))
    summary["variants"] = rows
    flat = pd.json_normalize(rows, sep=".").drop(columns=["retrospective_full_calibration"])
    flat.to_csv(os.path.join(OUT, "E37_two_stage_audit.csv"), index=False, float_format="%.5g")
    json.dump(summary, open(os.path.join(OUT, "E37_summary.json"), "w"), indent=2)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
