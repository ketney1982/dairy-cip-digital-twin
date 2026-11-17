# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E16 - Benchmark of the lumped cleaning kinetics against published experimental data (revision R2).

Input : ../outputs/E15_digitised_curves.csv (Zhang et al., 2025; Wiese et al., 2024)
Steps : 1. every curve is converted to the normalised residual soil y(t) = S(t)/S(0)
           (thickness: h/h0; tank concentration: 1 - C/C_plateau);
        2. structural test, curve by curve: first-order law of the simulator (M1), first-order
           with lag (M1L), uniform (zero-order) removal (M0) and two-stage linear removal (M2);
        3. calibration of the rate law r(T, v) = r_ref exp[alpha (T - 70)] (v / 1 cm/s)^beta on the
           calibration set (thickness curves at x = 16 cm: six velocities at 70 degC, plus 60 and
           50 degC), for M1 and M0, with leave-one-condition-out cross-validation and jackknife;
        4. validation on data not used for calibration: other axial positions, whole-channel
           protein curves (independent UV-Vis measurement) and an independent laboratory (Wiese).
Output: ../outputs/E16_*.csv / .json
"""
import os
import json
import numpy as np
import pandas as pd
from scipy.optimize import least_squares

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
T_REF, V_REF = 70.0, 1.0          # degC, cm/s
H0_MEAN = 2.44                    # mm, mean initial thickness reported by Zhang et al. (2025)
R_GAS = 8.314


# ----------------------------------------------------------------------------- data
def load_curves():
    d = pd.read_csv(os.path.join(OUT, "E15_digitised_curves.csv"))
    curves = []
    for (panel, series), g in d.groupby(["panel", "series"], sort=False):
        g = g.sort_values("t_min")
        q = g.quantity.iloc[0]
        t = g.t_min.to_numpy(float)
        v = g.value.to_numpy(float)
        if q in ("thickness_mm",):
            h0 = float(np.mean(v[:2]))
            y = v / h0
            kind = "thickness"
        elif q in ("tank_conc_g_L", "protein_conc_gWPIgel_per_Lsol"):
            cinf = float(np.mean(np.sort(v)[-3:]))
            y = 1.0 - v / cinf
            h0 = 3.0 if panel.startswith("W") else H0_MEAN
            kind = "protein"
            t = np.round(t) if panel.startswith("Z") else t       # samples were taken every minute
            if t[0] > 0.2:                                        # the curve starts at C = 0
                t = np.r_[0.0, t]
                y = np.r_[1.0, y]
        else:
            continue                                              # effluent (rate) curves and gel height: not used for fitting
        y = np.clip(y, 0.0, None)
        cid = f"{panel}:{series}"
        curves.append(dict(id=cid, panel=panel, series=series, kind=kind, T=float(g.T_C.iloc[0]),
                           v=float(g.v_cm_s.iloc[0]), x=float(g.x_cm.iloc[0]) if pd.notna(g.x_cm.iloc[0]) else np.nan,
                           h0=h0, t=t, y=y))
    return curves


def role(c):
    if c["panel"] == "Z6b" or (c["panel"] == "Z6c" and c["series"] in ("T=60", "T=50")):
        return "calibration"
    if c["panel"] == "Z6c" and c["series"] == "T=70":
        return "duplicate"                     # same condition as Z6b v=1.0 (plotted twice in the source)
    if c["panel"] == "Z6a" and c["series"] == "x=16cm":
        return "duplicate"
    if c["panel"] == "Z11c":
        return "duplicate"                     # Fig. 11c replots the 0.5 cm/s curve of Fig. 9a (same points; ordinates differ by a constant 2.3%)
    if c["panel"] == "Z6a":
        return "validation: other axial position"
    if c["panel"].startswith("Z") and c["kind"] == "protein":
        return "validation: whole-channel protein (UV-Vis)"
    if c["panel"].startswith("W"):
        return "validation: independent laboratory"
    return "other"


def t_cross(t, y, level):
    """First time at which y falls to `level` (linear interpolation); NaN if not reached."""
    below = np.where(y <= level)[0]
    if len(below) == 0:
        return np.nan
    i = below[0]
    if i == 0:
        return float(t[0])
    return float(t[i - 1] + (y[i - 1] - level) * (t[i] - t[i - 1]) / (y[i - 1] - y[i]))


# ----------------------------------------------------------------------------- models
def m1(t, k):
    return np.exp(-k * t)


def m1l(t, k, lag):
    return np.where(t < lag, 1.0, np.exp(-k * np.clip(t - lag, 0, None)))


def m0(t, tc):
    return np.clip(1.0 - t / tc, 0.0, None)


def m2(t, r1, tau, r2):
    ytau = 1.0 - r1 * tau
    return np.clip(np.where(t <= tau, 1.0 - r1 * t, ytau - r2 * (t - tau)), 0.0, None)


def fit(fun, p0, lo, hi, t, y):
    best = None
    for s in (1.0, 0.5, 2.0):
        try:
            r = least_squares(lambda p: fun(t, *p) - y, np.clip(np.array(p0) * s, lo, hi), bounds=(lo, hi))
        except Exception:
            continue
        if best is None or r.cost < best.cost:
            best = r
    res = fun(t, *best.x) - y
    n, k = len(y), len(p0)
    rss = float((res ** 2).sum())
    aicc = n * np.log(rss / n) + 2 * k + (2 * k * (k + 1)) / max(n - k - 1, 1)
    return best.x, float(np.sqrt(rss / n)), float(aicc)


def rate(T, v, p):
    """Rate multiplier law shared by M1 (k, 1/min) and M0 (r, mm/min)."""
    ref, alpha, beta = p
    return ref * np.exp(alpha * (np.asarray(T) - T_REF)) * (np.asarray(v) / V_REF) ** beta


def predict(c, p, model):
    if model == "M1":
        return m1(c["t"], rate(c["T"], c["v"], p))
    return m0(c["t"], c["h0"] / rate(c["T"], c["v"], p))


def calibrate(cs, model):
    def resid(p):
        out = []
        for c in cs:
            out.append((predict(c, p, model) - c["y"]) / np.sqrt(len(c["y"])))   # equal weight per curve
        return np.concatenate(out)
    p0 = [0.15, 0.06, 0.4]
    r = least_squares(resid, p0, bounds=([1e-4, 0.0, 0.0], [5.0, 0.3, 2.0]))
    return r.x


def metrics(c, yhat):
    e = yhat - c["y"]
    return dict(rmse=float(np.sqrt(np.mean(e ** 2))), mae=float(np.mean(np.abs(e))), bias=float(np.mean(e)),
                max_abs=float(np.max(np.abs(e))))


def main():
    curves = load_curves()
    for c in curves:
        c["role"] = role(c)

    # ---- 1. structural test, curve by curve
    rows = []
    for c in curves:
        t, y = c["t"], c["y"]
        tend = float(t[-1])
        p1, r1, a1 = fit(m1, [3.0 / tend], [1e-4], [10], t, y)
        p1l, r1l, a1l = fit(m1l, [3.0 / tend, 0.1 * tend], [1e-4, 0.0], [20, tend], t, y)
        p0_, r0, a0 = fit(m0, [tend], [0.2 * tend], [5 * tend], t, y)
        p2, r2, a2 = fit(m2, [0.6 / tend, 0.75 * tend, 2.0 / tend], [1e-4, 0.05 * tend, 1e-4], [5, tend, 20], t, y)
        t95, t50, t90 = t_cross(t, y, 0.05), t_cross(t, y, 0.5), t_cross(t, y, 0.10)
        rows.append(dict(curve=c["id"], role=c["role"], kind=c["kind"], T_C=c["T"], v_cm_s=c["v"], x_cm=c["x"], n=len(y),
                         h0_mm=c["h0"], t_end_obs_min=tend, t50_obs_min=t50, t90_obs_min=t90, t95_obs_min=t95,
                         M1_k_per_min=p1[0], M1_rmse=r1, M1_AICc=a1, M1_t90_min=np.log(10) / p1[0], M1_t95_min=np.log(20) / p1[0],
                         M1_S_at_tend=float(m1(tend, p1[0])),
                         M1L_k_per_min=p1l[0], M1L_lag_min=p1l[1], M1L_rmse=r1l, M1L_AICc=a1l,
                         M0_tc_min=p0_[0], M0_rmse=r0, M0_AICc=a0, M0_t90_min=0.90 * p0_[0], M0_t95_min=0.95 * p0_[0],
                         M2_r1=p2[0], M2_tau_min=p2[1], M2_r2=p2[2], M2_rmse=r2, M2_AICc=a2,
                         M2_rate_ratio=p2[2] / p2[0]))
    per = pd.DataFrame(rows)
    per.to_csv(os.path.join(OUT, "E16_per_curve_fits.csv"), index=False, float_format="%.5g")

    # ---- 2. calibration of the rate law on the calibration set
    cal = [c for c in curves if c["role"] == "calibration"]
    result = {"calibration_curves": [c["id"] for c in cal], "T_ref_C": T_REF, "v_ref_cm_s": V_REF}
    params = {}
    for model in ("M1", "M0"):
        p = calibrate(cal, model)
        jk = np.array([calibrate([c for c in cal if c is not d], model) for d in cal])
        n = len(cal)
        se = np.sqrt((n - 1) / n * ((jk - jk.mean(axis=0)) ** 2).sum(axis=0))
        # leave-one-condition-out prediction error
        loco = []
        for d, pj in zip(cal, jk):
            mt = metrics(d, predict(d, pj, model))
            t90o = t_cross(d["t"], d["y"], 0.10)
            t90p = (np.log(10) / rate(d["T"], d["v"], pj)) if model == "M1" else 0.90 * d["h0"] / rate(d["T"], d["v"], pj)
            loco.append(dict(curve=d["id"], model=model, **mt, t90_obs_min=t90o, t90_pred_min=float(t90p),
                             t90_ratio_pred_obs=float(t90p / t90o) if t90o == t90o else np.nan))
        params[model] = dict(p=p, se=se, jk=jk, loco=loco)
        Tk = T_REF + 273.15
        result[model] = dict(
            ref=float(p[0]), ref_unit="1/min" if model == "M1" else "mm/min",
            alpha_per_degC=float(p[1]), beta=float(p[2]),
            jackknife_se=dict(ref=float(se[0]), alpha=float(se[1]), beta=float(se[2])),
            apparent_activation_energy_kJ_mol=float(p[1] * R_GAS * 323.15 * 343.15 / 1000.0),
            fit_rmse_calibration=float(np.sqrt(np.mean(np.concatenate([(predict(c, p, model) - c["y"]) ** 2 for c in cal])))),
            loco_rmse=float(np.sqrt(np.mean([l["rmse"] ** 2 for l in loco]))),
            loco_log_t90_ratio_sd=float(np.nanstd(np.log([l["t90_ratio_pred_obs"] for l in loco]), ddof=1)),
        )
    pd.DataFrame(params["M1"]["loco"] + params["M0"]["loco"]).to_csv(
        os.path.join(OUT, "E16_leave_one_condition_out.csv"), index=False, float_format="%.5g")

    # ---- 3. validation on curves not used for calibration
    vrows, pred_rows = [], []
    for c in curves:
        for model in ("M1", "M0"):
            p = params[model]["p"]
            yhat = predict(c, p, model)
            mt = metrics(c, yhat)
            t90o = t_cross(c["t"], c["y"], 0.10)
            t90p = (np.log(10) / rate(c["T"], c["v"], p)) if model == "M1" else 0.90 * c["h0"] / rate(c["T"], c["v"], p)
            vrows.append(dict(curve=c["id"], role=c["role"], kind=c["kind"], T_C=c["T"], v_cm_s=c["v"], model=model, n=len(c["y"]), **mt,
                              t90_obs_min=t90o, t90_pred_min=float(t90p),
                              t90_ratio_pred_obs=float(t90p / t90o) if t90o == t90o else np.nan))
            for ti, yo, yp in zip(c["t"], c["y"], yhat):
                pred_rows.append(dict(curve=c["id"], role=c["role"], model=model, t_min=ti, y_obs=yo, y_pred=yp))
    val = pd.DataFrame(vrows)
    val.to_csv(os.path.join(OUT, "E16_validation_metrics.csv"), index=False, float_format="%.5g")
    pd.DataFrame(pred_rows).to_csv(os.path.join(OUT, "E16_observed_vs_predicted.csv"), index=False, float_format="%.5g")

    summ = (val[~val.role.isin(["duplicate"])].groupby(["role", "model"])
            .agg(n_curves=("curve", "size"), n_points=("n", "sum"),
                 rmse=("rmse", lambda s: float(np.sqrt(np.mean(s ** 2)))), mae=("mae", "mean"), bias=("bias", "mean"),
                 t90_ratio_min=("t90_ratio_pred_obs", "min"), t90_ratio_median=("t90_ratio_pred_obs", "median"),
                 t90_ratio_max=("t90_ratio_pred_obs", "max")).reset_index())
    summ.to_csv(os.path.join(OUT, "E16_validation_summary.csv"), index=False, float_format="%.4g")

    # ---- 4. comparison with the assumptions of the R1 simulator and published scalars
    sc = pd.read_csv(os.path.join(OUT, "E15_published_scalar_observations.csv"))
    water_removed = float(sc[sc.observation.str.contains("water flush")].value.iloc[0])
    frac_w = water_removed / H0_MEAN
    k_w = -np.log(1 - frac_w) / 10.0                                   # 1/min, first-order equivalent
    k_naoh = rate(70.0, 23.0, params["M1"]["p"])                        # 1/min at 70 degC, 23 cm/s
    r_w = water_removed / 10.0                                          # mm/min
    r_naoh = rate(70.0, 23.0, params["M0"]["p"])
    result["water_rinse"] = dict(removed_mm_in_10_min=water_removed, fraction_of_mean_h0=frac_w,
                                 k_water_per_min_first_order=float(k_w), k_NaOH_70C_23cms_per_min=float(k_naoh),
                                 ratio_first_order=float(k_w / k_naoh), r_water_mm_min=r_w, r_NaOH_70C_23cms_mm_min=float(r_naoh),
                                 ratio_uniform=float(r_w / r_naoh),
                                 note="water at 80 degC vs 0.5 wt% NaOH at 70 degC, both at 23 cm/s (Zhang et al., 2025)")
    result["R1_assumptions"] = dict(alpha_T_per_degC=0.035, beta_Q=0.45, k_pre_over_k_alk_at_reference=3.0,
                                    kinetic_order="first order in every phase")
    # run-to-run variability from replicate conditions and from validation residuals (log ratio of t95)
    v0 = val[(val.model == "M0") & val.role.str.startswith("validation") & ~val.role.str.contains("independent")]
    result["M0"]["validation_log_t90_ratio_mean"] = float(np.nanmean(np.log(v0.t90_ratio_pred_obs)))
    result["M0"]["validation_log_t90_ratio_sd"] = float(np.nanstd(np.log(v0.t90_ratio_pred_obs), ddof=1))
    v1 = val[(val.model == "M1") & val.role.str.startswith("validation") & ~val.role.str.contains("independent")]
    result["M1"]["validation_log_t90_ratio_mean"] = float(np.nanmean(np.log(v1.t90_ratio_pred_obs)))
    result["M1"]["validation_log_t90_ratio_sd"] = float(np.nanstd(np.log(v1.t90_ratio_pred_obs), ddof=1))
    # jackknife covariance (used by the audit of the calibrated case)
    for model in ("M1", "M0"):
        jk = params[model]["jk"]
        n = len(jk)
        lj = np.column_stack([np.log(jk[:, 0]), jk[:, 1], jk[:, 2]])
        cov = (n - 1) / n * (lj - lj.mean(axis=0)).T @ (lj - lj.mean(axis=0))
        result[model]["jackknife_cov_lnref_alpha_beta"] = cov.tolist()
    json.dump(result, open(os.path.join(OUT, "E16_calibrated_rate_law.json"), "w"), indent=2)

    pd.set_option("display.width", 250)
    print("STRUCTURAL TEST (per curve; RMSE of y)")
    print(per[["curve", "role", "n", "t90_obs_min", "t95_obs_min", "M1_rmse", "M1L_rmse", "M0_rmse", "M2_rmse", "M1_S_at_tend", "M1L_lag_min", "M2_rate_ratio"]]
          .round(3).to_string(index=False))
    use = per[per.role != "duplicate"]
    print("\nmedian RMSE  M1 %.3f | M1L %.3f | M0 %.3f | M2 %.3f ; best AICc counts:" % (
        use.M1_rmse.median(), use.M1L_rmse.median(), use.M0_rmse.median(), use.M2_rmse.median()),
        use[["M1_AICc", "M1L_AICc", "M0_AICc", "M2_AICc"]].idxmin(axis=1).value_counts().to_dict())
    print("\nCALIBRATED RATE LAW")
    for m in ("M1", "M0"):
        print(m, {k: (round(v, 4) if isinstance(v, float) else v) for k, v in result[m].items() if k != "jackknife_cov_lnref_alpha_beta"})
    print("\nwater rinse:", {k: (round(v, 4) if isinstance(v, float) else v) for k, v in result["water_rinse"].items()})
    print("\nVALIDATION SUMMARY"); print(summ.round(3).to_string(index=False))
    print("\nVALIDATION PER CURVE"); print(val[val.role != "duplicate"][["curve", "role", "model", "rmse", "bias", "t90_obs_min", "t90_pred_min", "t90_ratio_pred_obs"]].round(3).to_string(index=False))


if __name__ == "__main__":
    main()
