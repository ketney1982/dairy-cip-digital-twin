"""E26 - Checks added in revision R2.1 (audit of the calibrated case).

A. Domain-restricted audit: the U3 audit of the calibrated case draws realised temperature and velocity around the
   nominal setpoints, so that for recipes near the edge of the calibrated domain (50-70 degC, 0.5-23 cm/s) a share of
   the draws lies outside the domain in which the rate law was calibrated. Three variants are compared with the
   unrestricted audit of E17:
     V0  unrestricted (as in E17)
     V1  realised T and v clipped to the calibrated domain (the law is never evaluated outside it)
     V2  nominal setpoints restricted to T in [53, 67] degC and v in [0.556, 20.9] cm/s (2 sd from the domain edges),
         unclipped draws
     V3  V2 and clipping
B. Digitisation uncertainty propagated: random (per point) and systematic (per curve) errors of the digitised time and
   ordinate are added to all curves, the uniform-removal law is recalibrated, and the predicted-to-observed t90 of the
   validation curves and the wash times of the audit are recomputed (N_REP replicates).
C. Retrospective check: classification of each wash time as inside or after the last measured point.
D. Contributions of parameter covariance and prediction-error factor to the U3 margin (separately).
Output: ../outputs/E26_*.csv / .json
"""
import os, sys, json, importlib.util
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")


def load(name, fn):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fn))
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


e16 = load("e16_experimental_benchmark", "e16_experimental_benchmark.py")
e17 = load("e17_calibrated_case_audit", "e17_calibrated_case_audit.py")
FLOOR, Q = e17.FLOOR, e17.Q
TLO, THI, VLO, VHI = 50.0, 70.0, 0.5, 23.0
MODEL = "M0"


def audit_clip(T, v, t, d, clip, M=None):
    n = len(T)
    out = np.empty(n)
    low = np.empty(n)
    Mn = len(d["h0"])
    k = max(int(np.floor(Mn * Q - 1.96 * np.sqrt(Mn * Q * (1 - Q)))), 0)
    for s in range(0, n, 2000):
        sl = slice(s, s + 2000)
        Tm = T[sl, None] + d["dT"][None, :]
        vm = np.maximum(v[sl, None] * d["fv"][None, :], 1e-6)
        if clip:
            Tm = np.clip(Tm, TLO, THI)
            vm = np.clip(vm, VLO, VHI)
        h = e17.h_end(MODEL, Tm, vm, t[sl, None], d["h0"][None, :], d["p"][None, :, :], d["eps"][None, :])
        c = e17.cs(h)
        out[sl] = np.quantile(c, Q, axis=1)
        low[sl] = np.partition(c, k, axis=1)[:, k]
    return out, low


def outside_share(T, v, d):
    Tm = T + d["dT"]
    vm = v * d["fv"]
    return float(np.mean((Tm > THI) | (Tm < TLO) | (vm < VLO) | (vm > VHI))), float(np.mean(Tm > THI)), float(np.mean(vm < VLO))


def part_A():
    rng = np.random.default_rng(42)           # same candidates as E17
    u = rng.random((e17.N_CAND, 3))
    T = e17.LB["T"] + u[:, 0] * (e17.UB["T"] - e17.LB["T"])
    v = np.exp(np.log(e17.LB["v"]) + u[:, 1] * (np.log(e17.UB["v"]) - np.log(e17.LB["v"])))
    t = e17.LB["t"] + u[:, 2] * (e17.UB["t"] - e17.LB["t"])
    V, E = e17.burdens(T, v, t)
    p, _ = e17.pars(MODEL)
    nom = e17.cs(e17.h_end(MODEL, T, v, t, e17.H_NOM, p)) >= FLOOR
    d3 = e17.draws(MODEL, e17.M_CAND, 3, np.random.default_rng(103))      # same seed as E17 (100 + level)
    inside = (T >= 53) & (T <= 67) & (v >= 0.556) & (v <= 20.9)
    # share of candidates whose draws leave the domain
    rows, sels, fronts = [], [], {}
    res = {}
    for name, clip, restrict in (("V0 unrestricted", False, False), ("V1 clipped", True, False),
                                 ("V2 setpoints restricted", False, True), ("V3 restricted and clipped", True, True)):
        q, low = audit_clip(T, v, t, d3, clip)
        mask_domain = inside if restrict else np.ones(len(T), bool)
        nm = nom & mask_domain
        adm = nm & (q >= FLOOR)
        conf = nm & (low >= FLOOR)
        F = np.column_stack([V, E, t])
        idx = np.where(nm)[0]
        front = idx[e17.nondominated(F[idx])]
        res[name] = dict(q=q, low=low, nm=nm, conf=conf)
        rows.append(dict(variant=name, nominally_feasible=int(nm.sum()), admitted_point_estimate=int(adm.sum()),
                         admitted_confirmed_lower_limit=int(conf.sum()), nominal_front_size=len(front),
                         front_admitted=int((q[front] >= FLOOR).sum()),
                         front_q10_U3_min=float(q[front].min()), front_q10_U3_median=float(np.median(q[front])),
                         front_q10_U3_max=float(q[front].max())))
        # selections: nominal (min volume, min time) and audit-then-select among confirmed (min volume, min time)
        for scr, mask in (("nominal", nm), ("audit-then-select U3", conf)):
            sub = np.where(mask)[0]
            for sel, i in (("minimum volume", sub[np.argmin(V[sub])]), ("minimum time", sub[np.argmin(t[sub])])):
                # independent confirmation with M = 10,000
                dd = e17.draws(MODEL, e17.M_POLICY, 3, np.random.default_rng(903))
                Tm, vm = T[i] + dd["dT"], np.maximum(v[i] * dd["fv"], 1e-6)
                share = outside_share(T[i], v[i], dd)
                if clip:
                    Tm, vm = np.clip(Tm, TLO, THI), np.clip(vm, VLO, VHI)
                c = e17.cs(e17.h_end(MODEL, Tm, vm, t[i], dd["h0"], dd["p"], dd["eps"]))
                cs_sorted = np.sort(c)
                kk = int(np.floor(e17.M_POLICY * Q - 1.96 * np.sqrt(e17.M_POLICY * Q * (1 - Q))))
                sels.append(dict(variant=name, screening=scr, selection=sel, T_C=T[i], v_cm_s=v[i], t_min=t[i], V_L=V[i], E_kWh=E[i],
                                 q10_U3=float(np.quantile(c, Q)), q10_U3_lower95=float(cs_sorted[kk]),
                                 P_CS_ge_floor=float(np.mean(c >= FLOOR)), share_draws_outside_domain=share[0],
                                 share_T_above_70=share[1], share_v_below_0p5=share[2]))
    return pd.DataFrame(rows), pd.DataFrame(sels), (T, v, t, res, nom)


def part_A_grid():
    """Wash-time multiplier (robust / nominal) at the (T, v) grid of E17, unrestricted and clipped."""
    p, cov = e17.pars(MODEL)
    sig = e17.sigma_run(MODEL)
    out = []
    d3 = e17.draws(MODEL, e17.M_POLICY, 3, np.random.default_rng(903))
    d3p = dict(d3); d3p["eps"] = np.ones_like(d3["eps"])                 # parameter covariance only
    d3e = e17.draws(MODEL, e17.M_POLICY, 3, np.random.default_rng(903), par_unc=False)   # prediction-error factor only
    tt = np.linspace(0.2, 400, 6000)
    for Tc in (50.0, 60.0, 70.0):
        for vc in (0.5, 1.0, 1.5, 2.0, 12.0, 23.0):
            def tmin(d, clip):
                Tm = Tc + d["dT"][None, :]
                vm = np.maximum(vc * d["fv"][None, :], 1e-6)
                if clip:
                    Tm, vm = np.clip(Tm, TLO, THI), np.clip(vm, VLO, VHI)
                c = np.quantile(e17.cs(e17.h_end(MODEL, Tm, vm, tt[:, None], d["h0"][None, :], d["p"][None, :, :], d["eps"][None, :])), Q, axis=1)
                ok = np.where(c >= FLOOR)[0]
                return float(tt[ok[0]]) if len(ok) else np.nan
            c0 = e17.cs(e17.h_end(MODEL, Tc, vc, tt, e17.H_NOM, p))
            tn = float(tt[np.where(c0 >= FLOOR)[0][0]])
            row = dict(T_C=Tc, v_cm_s=vc, t_nominal=tn, t_U3=tmin(d3, False), t_U3_clipped=tmin(d3, True),
                       t_U3_params_only=tmin(d3p, False), t_U3_error_factor_only=tmin(d3e, False))
            for k_ in ("t_U3", "t_U3_clipped", "t_U3_params_only", "t_U3_error_factor_only"):
                row[k_.replace("t_", "ratio_")] = row[k_] / tn
            out.append(row)
    return pd.DataFrame(out)


def part_B(n_rep=300, s_t_rand=0.06, s_t_sys=0.06, s_y_rand=0.005, s_y_sys=0.002):
    """Digitisation error: random per point and systematic per curve (conservative: the largest axis-calibration
    residual of E15 is used as one standard deviation; the pixel resolution of the ordinate, 0.002 in y, as the
    systematic ordinate error and 2.5 times that as the random one)."""
    curves = e16.load_curves()
    for c in curves:
        c["role"] = e16.role(c)
    cal = [c for c in curves if c["role"] == "calibration"]
    val = [c for c in curves if c["role"].startswith("validation") and "independent" not in c["role"]]
    base = e16.calibrate(cal, MODEL)
    p0, cov0 = e17.pars(MODEL)
    sig0 = e17.sigma_run(MODEL)
    rng = np.random.default_rng(2611)

    def perturb(cs_):
        out = []
        for c in cs_:
            t = np.clip(c["t"] + rng.normal(0, s_t_sys) + rng.normal(0, s_t_rand, len(c["t"])), 0.0, None)
            order = np.argsort(t)
            y = c["y"] + rng.normal(0, s_y_sys) + rng.normal(0, s_y_rand, len(c["y"]))
            y = np.clip(y, 0.0, None)
            cc = dict(c); cc["t"] = t[order]; cc["y"] = y[order]
            out.append(cc)
        return out

    def ratio(c, p):
        r_ = e16.rate(c["T"], c["v"], p)
        return (0.90 * c["h0"] / r_) / e16.t_cross(c["t"], c["y"], 0.10)

    reps = []
    d3 = e17.draws(MODEL, 2000, 3, np.random.default_rng(55), p=p0, cov=cov0, sigma=sig0)
    tt = np.linspace(0.2, 120, 2400)
    for i in range(n_rep):
        cp, vp = perturb(cal), perturb(val)
        p = e16.calibrate(cp, MODEL)
        rv = np.array([ratio(c, p) for c in vp])
        tn = float(tt[np.where(e17.cs(e17.h_end(MODEL, 70.0, 1.0, tt, e17.H_NOM, p)) >= FLOOR)[0][0]])
        dd = dict(d3); dd["p"] = np.tile(p, (2000, 1)) * 1.0
        # parameter draws around the replicate: shift of the base draws
        dd["p"] = d3["p"] + (p - p0)
        c3 = np.quantile(e17.cs(e17.h_end(MODEL, 70.0 + dd["dT"][None, :], np.maximum(1.0 * dd["fv"][None, :], 1e-6), tt[:, None],
                                          dd["h0"][None, :], dd["p"][None, :, :], dd["eps"][None, :])), Q, axis=1)
        ok = np.where(c3 >= FLOOR)[0]
        tu3 = float(tt[ok[0]]) if len(ok) else np.nan
        reps.append(dict(rep=i, rref=p[0], alpha=p[1], beta=p[2], ratio_min=rv.min(), ratio_max=rv.max(), ratio_med=np.median(rv),
                         t_nominal_70_1=tn, t_U3_70_1=tu3, margin_70_1=tu3 / tn))
    R = pd.DataFrame(reps)
    unperturbed = np.array([ratio(c, base) for c in val])
    summ = {}
    for col in ("rref", "alpha", "beta", "ratio_min", "ratio_max", "ratio_med", "t_nominal_70_1", "t_U3_70_1", "margin_70_1"):
        summ[col] = dict(mean=float(R[col].mean()), sd=float(R[col].std(ddof=1)), p2_5=float(R[col].quantile(0.025)), p97_5=float(R[col].quantile(0.975)))
    summ["unperturbed_ratio_min_max_median"] = [float(unperturbed.min()), float(unperturbed.max()), float(np.median(unperturbed))]
    summ["base_parameters"] = [float(x) for x in base]
    summ["jackknife_se"] = [float(x) for x in e17.cal[MODEL]["jackknife_se"].values()]
    summ["settings"] = dict(n_rep=n_rep, s_t_rand=s_t_rand, s_t_sys=s_t_sys, s_y_rand=s_y_rand, s_y_sys=s_y_sys)
    return R, summ


def part_C():
    cv = pd.read_csv(os.path.join(OUT, "E17_retrospective_check_crossvalidated.csv"))
    cv = cv[cv.model == MODEL].copy()                       # t_end_obs_min and within_record are written by e17
    cv["status"] = np.where(cv.within_record.astype(bool), "within measured range", "after last measured point")
    # after the last measured point nothing was observed at the wash time (observed_CS is empty); the score of the
    # last measured point is in last_measured_CS and is not an observation at the prescribed time
    cv["outcome"] = np.where(cv.status == "after last measured point", "not observed (wash time after last measured point)",
                             np.where(cv.observed_CS >= 95.0, "observed clean", "observed below floor"))
    tab = cv.pivot_table(index="wash_time_rule", columns="outcome", values="curve", aggfunc="count", fill_value=0)
    return cv, tab


if __name__ == "__main__":
    which = sys.argv[1:] or ["A", "B", "C"]
    pd.set_option("display.width", 250); pd.set_option("display.max_columns", 50)
    if "C" in which:
        cv, tab = part_C()
        cv.to_csv(os.path.join(OUT, "E26_C_retrospective_status.csv"), index=False, float_format="%.5g")
        print(tab); print(cv[cv.wash_time_rule == "U3"][["curve", "T_C", "v_cm_s", "wash_time_min", "t_end_obs_min", "status", "observed_CS", "last_measured_CS"]].round(2).to_string(index=False))
        print(cv[cv.wash_time_rule == "nominal"][["curve", "wash_time_min", "t_end_obs_min", "status", "observed_CS"]].round(2).to_string(index=False))
        print(cv[cv.wash_time_rule == "U0"][["curve", "wash_time_min", "t_end_obs_min", "status", "observed_CS"]].round(2).to_string(index=False))
    if "A" in which:
        rowsA, selsA, _ = part_A()
        rowsA.to_csv(os.path.join(OUT, "E26_A_domain_restricted_counts.csv"), index=False, float_format="%.5g")
        selsA.to_csv(os.path.join(OUT, "E26_A_domain_restricted_selected.csv"), index=False, float_format="%.5g")
        print(rowsA.round(2).to_string(index=False)); print(selsA.round(3).to_string(index=False))
        g = part_A_grid()
        g.to_csv(os.path.join(OUT, "E26_A_wash_time_ratios.csv"), index=False, float_format="%.5g")
        print(g.round(2).to_string(index=False))
        print(g[[c for c in g.columns if c.startswith("ratio_")]].agg(["min", "median", "max"]).round(2))
    if "B" in which:
        R, summ = part_B()
        R.to_csv(os.path.join(OUT, "E26_B_digitisation_replicates.csv"), index=False, float_format="%.5g")
        json.dump(summ, open(os.path.join(OUT, "E26_B_digitisation_summary.json"), "w"), indent=1)
        print(json.dumps(summ, indent=1))
