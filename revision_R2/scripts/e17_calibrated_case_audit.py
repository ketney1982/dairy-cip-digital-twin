# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E17 - Robustness audit of the experimentally calibrated case (revision R2).

The audit procedure of the manuscript (nominal screening -> Monte Carlo audit -> audit-then-select)
is applied to the laboratory flow channel of Zhang et al. (2025), for which the removal kinetics were
calibrated and validated in E16. Alkaline step only (0.5 wt% NaOH, once-through), decision variables
T (50-70 degC), v (0.5-23 cm/s) and wash time t (1-90 min): the calibrated domain.

  residual thickness, uniform law (M0):  h_end = max(0, h0 - eps * r(T, v) * t)
  residual thickness, first-order (M1):  h_end = h0 * exp(-eps * k(T, v) * t)
  cleaning score: CS = 100 (1 - h_end / h_ref), h_ref = 3 mm (heaviest reported deposit)
  burdens: solution volume V = v A t; thermal energy E = rho cp V (T - Tin) / eta_heater

Uncertainty sets (data-derived where possible):
  U0  initial deposit thickness h0 ~ U(2, 3) mm (range reported by Zhang et al.)
  U1  U0 + setpoint errors: T ~ N(T, 1.5 degC), v (1 + N(0, 0.05))
  U2  U1 + inlet-water temperature Tin ~ U(5, 25 degC)   (energy only)
  U3  U2 + kinetics: (ln r_ref, alpha, beta) ~ N(estimate, jackknife covariance) and a run-to-run
      factor eps ~ LN(0, sigma), sigma = SD of ln(predicted/observed t90) in E16
Also: retrospective check of nominal and robust wash times against the observed cleaning curves. A measured curve is
read only inside its record: for a wash time after the last measured point the fields observed_CS / observed_pass
are left empty (within_record = False) and the score of the last measured point is given in last_measured_CS; the
time at which the measured curve first crossed the floor is given in t_floor_crossing_obs_min (function read_curve).
Output: ../outputs/E17_*.csv / .json
"""
import os
import json
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")
cal = json.load(open(os.path.join(OUT, "E16_calibrated_rate_law.json")))

A_C = 3.0 * 0.6          # cm2, channel cross-section (W = 3 cm, H = 0.6 cm)
H_REF, H_NOM = 3.0, 2.44  # mm
RHO, CP, ETA_HEATER, TIN = 1000.0, 4.186, 0.85, 15.0
FLOOR, Q = 95.0, 0.10
LB = dict(T=50.0, v=0.5, t=1.0)
UB = dict(T=70.0, v=23.0, t=90.0)
N_CAND, M_CAND, M_POLICY = 30000, 4000, 10000


def pars(model):
    c = cal[model]
    return np.array([c["ref"], c["alpha_per_degC"], c["beta"]]), np.array(c["jackknife_cov_lnref_alpha_beta"])


def sigma_run(model):
    c = cal[model]
    return float(np.sqrt(0.5 * (c["loco_log_t90_ratio_sd"] ** 2 + c["validation_log_t90_ratio_sd"] ** 2)))


def rate(T, v, p):
    return p[..., 0] * np.exp(p[..., 1] * (T - cal["T_ref_C"])) * (v / cal["v_ref_cm_s"]) ** p[..., 2]


def h_end(model, T, v, t, h0, p, eps=1.0):
    r = rate(T, v, p) * eps
    if model == "M0":
        return np.maximum(h0 - r * t, 0.0)
    return h0 * np.exp(-r * t)


def cs(h):
    return 100.0 * (1.0 - h / H_REF)


def burdens(T, v, t, Tin=TIN):
    V = v * A_C * t * 60.0 / 1000.0                                  # L
    E = RHO * (V / 1000.0) * CP * np.maximum(T - Tin, 0.0) / ETA_HEATER / 3600.0   # kWh
    return V, E


def draws(model, M, level, rng, p=None, cov=None, sigma=None, par_unc=True):
    """Common random numbers for one audit (level 0..3). p, cov, sigma default to the full calibration;
    par_unc=False keeps the prediction-error factor but drops the parameter covariance."""
    if p is None:
        p, cov = pars(model)
    sigma = sigma_run(model) if sigma is None else sigma
    d = dict(h0=rng.uniform(2.0, 3.0, M), dT=np.zeros(M), fv=np.ones(M), Tin=np.full(M, TIN),
             p=np.tile(p, (M, 1)), eps=np.ones(M))
    zT, zv, uT = rng.normal(0, 1.5, M), rng.normal(0, 0.05, M), rng.uniform(5, 25, M)
    L = np.linalg.cholesky(cov + 1e-12 * np.eye(3))
    z = rng.normal(size=(M, 3)) @ L.T
    e = rng.normal(0, sigma, M)
    if level >= 1:
        d["dT"], d["fv"] = zT, 1 + zv
    if level >= 2:
        d["Tin"] = uT
    if level >= 3:
        if par_unc:
            d["p"] = np.column_stack([p[0] * np.exp(z[:, 0]), p[1] + z[:, 1], p[2] + z[:, 2]])
        d["eps"] = np.exp(e)
    return d


def wash_time(model, Tc, vc, p, d=None, tmax=600.0):
    """Shortest wash time meeting CS >= floor at nominal thickness (d None) or q0.10(CS) >= floor under the draws d."""
    tt = np.linspace(0.2, tmax, 12000)
    if d is None:
        c = cs(h_end(model, Tc, vc, tt, H_NOM, p))
    else:
        c = np.quantile(cs(h_end(model, Tc + d["dT"][None, :], np.maximum(vc * d["fv"][None, :], 1e-6), tt[:, None],
                                 d["h0"][None, :], d["p"][None, :, :], d["eps"][None, :])), Q, axis=1)
    ok = np.where(c >= FLOOR)[0]
    return float(tt[ok[0]]) if len(ok) else np.nan


def audit(model, T, v, t, d):
    """q0.10(CS) and its distribution-free lower 95% confidence limit for candidates (length n) under the draws d (length M)."""
    n = len(T)
    M = len(d["h0"])
    k = max(int(np.floor(M * Q - 1.96 * np.sqrt(M * Q * (1 - Q)))), 0)
    out = np.empty(n)
    low = np.empty(n)
    for s in range(0, n, 2000):
        sl = slice(s, s + 2000)
        Tm = T[sl, None] + d["dT"][None, :]
        vm = np.maximum(v[sl, None] * d["fv"][None, :], 1e-6)
        h = h_end(model, Tm, vm, t[sl, None], d["h0"][None, :], d["p"][None, :, :], d["eps"][None, :])
        c = cs(h)
        out[sl] = np.quantile(c, Q, axis=1)
        low[sl] = np.partition(c, k, axis=1)[:, k]
    return out, low


def nondominated(F):
    """Indices of the non-dominated rows of F (all objectives minimised)."""
    order = np.lexsort(F.T[::-1])
    F = F[order]
    keep = np.ones(len(F), bool)
    for i in range(len(F)):
        if not keep[i]:
            continue
        dom = np.all(F[i] <= F, axis=1) & np.any(F[i] < F, axis=1)
        keep &= ~dom
        keep[i] = True
    return order[keep]


def read_curve(tw, t, y, h0):
    """Cleaning score of a measured curve (times t, normalised residual soil y, initial thickness h0) at the wash time tw.

    The curve is read by linear interpolation only inside the measured record. If tw lies after the last measured
    point, nothing was observed at tw: the 'observed' fields stay empty, and the score of the last measured point is
    reported in fields of its own. The time at which the measured curve first crosses the floor (linear interpolation
    between the two neighbouring points) is reported separately; it answers a different question (had the floor been
    crossed by tw?) from the score at tw."""
    t = np.asarray(t, float)
    y = np.asarray(y, float)
    c = 100.0 * (1.0 - y * h0 / H_REF)
    within = bool(tw <= t[-1])
    k = np.where(c >= FLOOR)[0]
    if len(k) == 0:
        t_cross = np.nan
    elif k[0] == 0:
        t_cross = float(t[0])
    else:
        a = k[0]
        t_cross = float(t[a - 1] + (FLOOR - c[a - 1]) * (t[a] - t[a - 1]) / (c[a] - c[a - 1]))
    y_tw = float(np.interp(tw, t, y)) if within else np.nan
    c_tw = 100.0 * (1.0 - y_tw * h0 / H_REF) if within else np.nan
    return dict(t_end_obs_min=float(t[-1]), within_record=within, observed_residual_fraction=y_tw, observed_CS=c_tw,
                observed_pass=bool(c_tw >= FLOOR) if within else None,
                last_measured_CS=float(c[-1]), last_measured_pass=bool(c[-1] >= FLOOR),
                t_floor_crossing_obs_min=t_cross, floor_crossed_by_wash_time=bool(np.isfinite(t_cross) and t_cross <= tw))


def retro_summary(df, by):
    """Counts of the retrospective check; curves whose wash time lies after the record are counted separately."""
    w = df.within_record.astype(bool)
    ok = (df.observed_CS >= FLOOR).fillna(False).astype(bool)   # empty (not observed) counts neither as pass nor as fail
    d = df.assign(n_within_record=w, n_observed_pass=w & ok, n_observed_fail=w & ~ok, n_after_record=~w,
                  n_after_record_last_point_pass=~w & df.last_measured_pass.astype(bool),
                  n_floor_crossed_by_wash_time=df.floor_crossed_by_wash_time.astype(bool))
    cols = ["n_within_record", "n_observed_pass", "n_observed_fail", "n_after_record", "n_after_record_last_point_pass",
            "n_floor_crossed_by_wash_time"]
    g = d.groupby(by)
    out = g[cols].sum().astype(int)
    out.insert(0, "n_curves", g.size())
    out["min_observed_CS"] = g.observed_CS.min()                # within the record only (empty if no curve extends to tw)
    out["min_last_measured_CS_after_record"] = d[~w].groupby(by).last_measured_CS.min()
    return out.reset_index()


def records(df):
    """Rows as dictionaries with empty cells written as null (valid JSON)."""
    return json.loads(df.to_json(orient="records"))


def main():
    rng = np.random.default_rng(42)
    u = rng.random((N_CAND, 3))
    T = LB["T"] + u[:, 0] * (UB["T"] - LB["T"])
    v = np.exp(np.log(LB["v"]) + u[:, 1] * (np.log(UB["v"]) - np.log(LB["v"])))   # log-uniform: the range spans a factor of 46
    t = LB["t"] + u[:, 2] * (UB["t"] - LB["t"])
    V, E = burdens(T, v, t)
    res = pd.DataFrame(dict(T_C=T, v_cm_s=v, t_min=t, V_L=V, E_kWh=E))
    summary = dict(case="laboratory flow channel (Zhang et al., 2025), 0.5 wt% NaOH", n_candidates=N_CAND,
                   M_candidates=M_CAND, floor=FLOOR, quantile=Q, h_ref_mm=H_REF, h_nominal_mm=H_NOM,
                   sigma_run_to_run={m: sigma_run(m) for m in ("M0", "M1")})

    for model in ("M0", "M1"):
        p, _ = pars(model)
        res[f"CS_nom_{model}"] = cs(h_end(model, T, v, t, H_NOM, p))
        for level in (0, 3):
            d = draws(model, M_CAND, level, np.random.default_rng(100 + level))
            res[f"q10_U{level}_{model}"], res[f"q10low_U{level}_{model}"] = audit(model, T, v, t, d)
        # deterministic design-load checks (no Monte Carlo)
        res[f"CS_h0_2p9_{model}"] = cs(h_end(model, T, v, t, 2.9, p))
        res[f"CS_h0_3p0_{model}"] = cs(h_end(model, T, v, t, 3.0, p))
    res.to_csv(os.path.join(OUT, "E17_candidates.csv"), index=False, float_format="%.5g")

    rows = []
    fronts = []
    for model in ("M0", "M1"):
        nom = (res[f"CS_nom_{model}"] >= FLOOR).to_numpy()
        a0 = nom & (res[f"q10_U0_{model}"] >= FLOOR).to_numpy()
        a3 = nom & (res[f"q10_U3_{model}"] >= FLOOR).to_numpy()
        c0 = nom & (res[f"q10low_U0_{model}"] >= FLOOR).to_numpy()      # conservative rule: lower 95% limit of q0.10(CS) reaches the floor
        c3 = nom & (res[f"q10low_U3_{model}"] >= FLOOR).to_numpy()
        d29 = nom & (res[f"CS_h0_2p9_{model}"] >= FLOOR).to_numpy()
        d30 = nom & (res[f"CS_h0_3p0_{model}"] >= FLOOR).to_numpy()
        F = res[["V_L", "E_kWh", "t_min"]].to_numpy()
        idx_nom = np.where(nom)[0]
        front = idx_nom[nondominated(F[idx_nom])]
        fr = res.iloc[front]
        summary[model] = dict(
            nominally_feasible=int(nom.sum()), admitted_U0=int(a0.sum()), admitted_U3=int(a3.sum()),
            confirmed_U0=int(c0.sum()), confirmed_U3=int(c3.sum()),
            det_check_h0_2p9=int(d29.sum()), det_check_h0_3p0=int(d30.sum()),
            det_2p9_admitted_but_fail_U3=int((d29 & ~a3).sum()), det_3p0_admitted_but_fail_U3=int((d30 & ~a3).sum()),
            U3_admitted_but_fail_det_3p0=int((a3 & ~d30).sum()),
            nominal_front_size=int(len(front)),
            nominal_front_admitted_U0=int((fr[f"q10_U0_{model}"] >= FLOOR).sum()),
            nominal_front_admitted_U3=int((fr[f"q10_U3_{model}"] >= FLOOR).sum()),
            nominal_front_q10_U3_min=float(fr[f"q10_U3_{model}"].min()), nominal_front_q10_U3_median=float(fr[f"q10_U3_{model}"].median()),
            nominal_front_q10_U3_max=float(fr[f"q10_U3_{model}"].max()),
            nominal_front_CS_nom_median=float(fr[f"CS_nom_{model}"].median()), nominal_front_CS_nom_max=float(fr[f"CS_nom_{model}"].max()))
        for name, mask in (("nominal", nom), ("U0", c0), ("U3", c3)):
            sub = res[mask]
            ids = sub.index[nondominated(sub[["V_L", "E_kWh", "t_min"]].to_numpy())]
            f2 = res.loc[ids].assign(model=model, screening=name)
            fronts.append(f2)
            # selections: minimum volume, minimum energy, minimum time, and equal-weight compromise
            nrm = (sub[["V_L", "E_kWh", "t_min"]] - sub[["V_L", "E_kWh", "t_min"]].min()) / (
                sub[["V_L", "E_kWh", "t_min"]].max() - sub[["V_L", "E_kWh", "t_min"]].min())
            picks = dict(min_volume=sub.V_L.idxmin(), min_energy=sub.E_kWh.idxmin(), min_time=sub.t_min.idxmin(),
                         balanced=nrm.sum(axis=1).idxmin())
            for sel, i in picks.items():
                r = res.loc[i]
                rows.append(dict(model=model, screening=name, selection=sel, n_admitted=int(mask.sum()), T_C=r.T_C, v_cm_s=r.v_cm_s,
                                 t_min=r.t_min, V_L=r.V_L, E_kWh=r.E_kWh, CS_nom=r[f"CS_nom_{model}"],
                                 q10_U0=r[f"q10_U0_{model}"], q10_U3=r[f"q10_U3_{model}"], candidate=int(i)))
    sel = pd.DataFrame(rows)

    # confirmation of the selected recipes with an independent, larger sample under U0..U3 (M = 10,000)
    conf = []
    for _, r in sel.iterrows():
        for level in (0, 1, 2, 3):
            d = draws(r.model, M_POLICY, level, np.random.default_rng(900 + level))
            Tm = r.T_C + d["dT"]
            vm = np.maximum(r.v_cm_s * d["fv"], 1e-6)
            c = cs(h_end(r.model, Tm, vm, r.t_min, d["h0"], d["p"], d["eps"]))
            c_sorted = np.sort(c)
            k = int(np.floor(M_POLICY * Q - 1.96 * np.sqrt(M_POLICY * Q * (1 - Q))))   # distribution-free lower 95% limit
            Vd, Ed = burdens(Tm, vm, r.t_min, d["Tin"])
            conf.append(dict(model=r.model, screening=r.screening, selection=r.selection, U=f"U{level}",
                             q10_CS=float(np.quantile(c, Q)), q10_CS_lower95=float(c_sorted[max(k, 0)]),
                             P_CS_ge_floor=float(np.mean(c >= FLOOR)), q90_E_kWh=float(np.quantile(Ed, 0.9)), q90_V_L=float(np.quantile(Vd, 0.9))))
    conf = pd.DataFrame(conf)
    sel = sel.merge(conf[conf.U == "U3"][["model", "screening", "selection", "q10_CS", "q10_CS_lower95", "P_CS_ge_floor"]]
                    .rename(columns={"q10_CS": "q10_U3_M10000", "q10_CS_lower95": "q10_U3_lower95", "P_CS_ge_floor": "P_U3_CS_ge_floor"}),
                    on=["model", "screening", "selection"])
    sel.to_csv(os.path.join(OUT, "E17_selected_recipes.csv"), index=False, float_format="%.5g")
    conf.to_csv(os.path.join(OUT, "E17_selected_recipes_U0_U3.csv"), index=False, float_format="%.5g")
    pd.concat(fronts).to_csv(os.path.join(OUT, "E17_fronts.csv"), index=False, float_format="%.5g")

    # price of robustness at fixed (T, v): wash time needed nominally and under U0 / U3
    grid = []
    for model in ("M0", "M1"):
        p, _ = pars(model)
        d0 = draws(model, M_POLICY, 0, np.random.default_rng(900))
        d3 = draws(model, M_POLICY, 3, np.random.default_rng(903))
        d3e = draws(model, M_POLICY, 3, np.random.default_rng(903), par_unc=False)
        for Tc in (50.0, 60.0, 70.0):
            for vc in (0.5, 1.0, 1.5, 2.0, 12.0, 23.0):
                tt = np.linspace(0.2, 400, 8000)
                def tmin(d):
                    if d is None:
                        c = cs(h_end(model, Tc, vc, tt, H_NOM, p))
                    else:
                        c = np.quantile(cs(h_end(model, Tc + d["dT"][None, :], np.maximum(vc * d["fv"][None, :], 1e-6), tt[:, None],
                                                 d["h0"][None, :], d["p"][None, :, :], d["eps"][None, :])), Q, axis=1)
                    ok = np.where(c >= FLOOR)[0]
                    return float(tt[ok[0]]) if len(ok) else np.nan
                grid.append(dict(model=model, T_C=Tc, v_cm_s=vc, t_nominal_min=tmin(None), t_U0_min=tmin(d0), t_U3_min=tmin(d3),
                                 t_U3_prediction_error_only_min=tmin(d3e)))
    grid = pd.DataFrame(grid)
    grid["U0_over_nominal"] = grid.t_U0_min / grid.t_nominal_min
    grid["U3_over_nominal"] = grid.t_U3_min / grid.t_nominal_min
    grid["U3_prediction_error_only_over_nominal"] = grid.t_U3_prediction_error_only_min / grid.t_nominal_min
    grid.to_csv(os.path.join(OUT, "E17_required_wash_time.csv"), index=False, float_format="%.5g")

    # retrospective check against the observed curves: residual observed at the nominal and robust wash times
    dig = pd.read_csv(os.path.join(OUT, "E15_digitised_curves.csv"))
    per = pd.read_csv(os.path.join(OUT, "E16_per_curve_fits.csv"))
    obs = pd.read_csv(os.path.join(OUT, "E16_observed_vs_predicted.csv"))
    obs = obs[obs.model == "M0"]
    retro = []
    for _, c in per[(per.role != "duplicate") & ~per.role.str.contains("independent")].iterrows():
        g = obs[obs.curve == c.curve].sort_values("t_min")
        for model in ("M0", "M1"):
            gr = grid[(grid.model == model) & (grid.T_C == c.T_C) & (np.isclose(grid.v_cm_s, c.v_cm_s))]
            if gr.empty:
                continue
            gr = gr.iloc[0]
            for label, tw in (("nominal", gr.t_nominal_min), ("U0", gr.t_U0_min), ("U3", gr.t_U3_min)):
                retro.append(dict(curve=c.curve, role=c.role, T_C=c.T_C, v_cm_s=c.v_cm_s, model=model, wash_time_rule=label,
                                  wash_time_min=tw, **read_curve(tw, g.t_min, g.y_obs, c.h0_mm)))
    retro = pd.DataFrame(retro)
    retro.to_csv(os.path.join(OUT, "E17_retrospective_check.csv"), index=False, float_format="%.5g")
    rs = retro_summary(retro, ["model", "wash_time_rule"]).merge(
        retro.groupby(["model", "wash_time_rule"]).wash_time_min.median().rename("median_wash_time").reset_index())
    rs.to_csv(os.path.join(OUT, "E17_retrospective_summary.csv"), index=False, float_format="%.5g")
    summary["retrospective"] = records(rs)

    # ---- cross-validated retrospective check: for the condition (T, v) of each measured curve, the rate law, its jackknife
    # covariance and the prediction-error factor are re-estimated WITHOUT any curve measured at that condition
    import importlib.util
    spec = importlib.util.spec_from_file_location("e16", os.path.join(HERE, "e16_experimental_benchmark.py"))
    e16 = importlib.util.module_from_spec(spec); spec.loader.exec_module(e16)
    curves = e16.load_curves()
    for c in curves:
        c["role"] = e16.role(c)
    inlab = [c for c in curves if c["role"] != "duplicate" and "independent" not in c["role"]]
    cvrows = []
    for (Tc, vc) in sorted({(c["T"], c["v"]) for c in inlab}):
        other = [c for c in inlab if (c["T"], c["v"]) != (Tc, vc)]
        calset = [c for c in other if c["role"] == "calibration"]
        valset = [c for c in other if c["role"] != "calibration"]
        for model in ("M0", "M1"):
            p = e16.calibrate(calset, model)
            jk = np.array([e16.calibrate([c for c in calset if c is not dd], model) for dd in calset])
            n = len(calset)
            lj = np.column_stack([np.log(jk[:, 0]), jk[:, 1], jk[:, 2]])
            cov = (n - 1) / n * (lj - lj.mean(axis=0)).T @ (lj - lj.mean(axis=0))

            def ratio(c, pp):
                r_ = e16.rate(c["T"], c["v"], pp)
                tp = (np.log(10) / r_) if model == "M1" else 0.90 * c["h0"] / r_
                return tp / e16.t_cross(c["t"], c["y"], 0.10)
            sd_loco = np.std(np.log([ratio(dd, pj) for dd, pj in zip(calset, jk)]), ddof=1)
            sd_val = np.std(np.log([ratio(c, p) for c in valset]), ddof=1) if len(valset) > 1 else sd_loco
            sig = float(np.sqrt(0.5 * (sd_loco ** 2 + sd_val ** 2)))
            t_nom = wash_time(model, Tc, vc, p)
            t_u0 = wash_time(model, Tc, vc, p, draws(model, M_POLICY, 0, np.random.default_rng(900), p=p, cov=cov, sigma=sig))
            t_u3 = wash_time(model, Tc, vc, p, draws(model, M_POLICY, 3, np.random.default_rng(903), p=p, cov=cov, sigma=sig))
            for c in [c for c in inlab if (c["T"], c["v"]) == (Tc, vc)]:
                for label, tw in (("nominal", t_nom), ("U0", t_u0), ("U3", t_u3)):
                    cvrows.append(dict(curve=c["id"], role=c["role"], T_C=Tc, v_cm_s=vc, model=model, wash_time_rule=label, wash_time_min=tw,
                                       n_calibration_curves=n, sigma_prediction_error=sig, **read_curve(tw, c["t"], c["y"], c["h0"])))
    cv = pd.DataFrame(cvrows)
    cv.to_csv(os.path.join(OUT, "E17_retrospective_check_crossvalidated.csv"), index=False, float_format="%.5g")
    cvs = retro_summary(cv, ["model", "wash_time_rule"])
    cvs.to_csv(os.path.join(OUT, "E17_retrospective_crossvalidated_summary.csv"), index=False, float_format="%.5g")
    summary["retrospective_crossvalidated"] = records(cvs)
    rv = retro_summary(retro[retro.role != "calibration"], ["model", "wash_time_rule"])
    summary["retrospective_validation_curves_only"] = records(rv)
    summary["price_of_robustness_time_ratio"] = {
        m: dict(U0_median=float(grid[grid.model == m].U0_over_nominal.median()), U3_median=float(grid[grid.model == m].U3_over_nominal.median()),
                U3_min=float(grid[grid.model == m].U3_over_nominal.min()), U3_max=float(grid[grid.model == m].U3_over_nominal.max()))
        for m in ("M0", "M1")}
    json.dump(summary, open(os.path.join(OUT, "E17_summary.json"), "w"), indent=2)

    pd.set_option("display.width", 250)
    print(json.dumps({k: v for k, v in summary.items() if not k.startswith("retrospective")}, indent=1)[:1500])
    print(sel.drop(columns=["candidate"]).round(3).to_string(index=False))
    print(grid.round(2).to_string(index=False))
    print(rs.round(2).to_string(index=False))
    print("validation curves only:"); print(rv.round(2).to_string(index=False))
    print("cross-validated:"); print(cvs.round(2).to_string(index=False))
    show = ["curve", "T_C", "v_cm_s", "wash_time_rule", "wash_time_min", "t_end_obs_min", "within_record", "observed_CS",
            "last_measured_CS", "t_floor_crossing_obs_min"]
    print(cv[cv.model == "M0"][show].round(1).to_string(index=False))
    print(grid.groupby("model")[["U0_over_nominal", "U3_prediction_error_only_over_nominal", "U3_over_nominal"]].agg(["min", "median", "max"]).round(2))
    print("full calibration:"); print(retro[retro.model == "M0"][show].round(1).to_string(index=False))


if __name__ == "__main__":
    main()
