# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E24 - Tests of the calibrated rate law beyond the calibration data (revision R2).

The rate law calibrated in E16 (and its audit, E17) was fixed before the data used here were examined.

  A  New condition, same apparatus: thickness curve at 75 degC and 23.65 cm/s (0.5 wt% NaOH) of
     Zhang et al. (2026), Fig. 8b - a temperature above the calibrated range (50-70 degC).
     Predicted versus observed time to 90% removal, and the audit rule applied to the unseen condition.
  B  Equipment scale: laboratory plate heat exchanger of Zhang et al. (2026), Figs. 5 and 9d.
     Required cleaning times at four velocities, four temperatures and three NaOH concentrations versus
     the time predicted for uniform removal of the mean deposit thickness at the flat-channel rate.
  C  Other laboratories and soils: plateau (uniform-stage) removal fluxes of Gillham et al. (1999,
     Table 3, isothermal runs) and Xin et al. (2004, Tables 1 and 2) versus the calibrated law
     expressed per unit of dry matter.
  D  Published sensitivities (apparent activation energy, velocity exponent, order in NaOH
     concentration) versus the calibrated values and the assumptions of the illustrative case.

Digitised: Zhang et al. (2026) Chem. Eng. Sci. 320, 122395 (CC BY 4.0), images in
../source_data/published_figures. Tabulated values of the other sources are transcribed below with
their location. Output: ../outputs/E24_*.csv / .json
"""
import os
import json
import importlib.util
import numpy as np
import pandas as pd
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
FIG = os.path.join(HERE, "..", "source_data", "published_figures")
OUT = os.path.join(HERE, "..", "outputs")


def _load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, {"e16": "e16_experimental_benchmark.py",
                                                                         "e17": "e17_calibrated_case_audit.py"}[name]))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


e16, e17 = _load("e16"), _load("e17")
cal = json.load(open(os.path.join(OUT, "E16_calibrated_rate_law.json")))
P = {m: np.array([cal[m]["ref"], cal[m]["alpha_per_degC"], cal[m]["beta"]]) for m in ("M0", "M1")}
COV = {m: np.array(cal[m]["jackknife_cov_lnref_alpha_beta"]) for m in ("M0", "M1")}
T_CAL, V_CAL = (50.0, 70.0), (0.5, 23.0)          # calibrated ranges (degC, cm/s)
R_GAS = 8.314

# ------------------------------------------------------------------ axis calibration (pixel, value) on grid lines
PANELS = {
    "Z26_8b": dict(img="Zhang2026_CES_Fig8.png", box=(367, 1099, 395, 973),
                   xcal=[(367, 0), (488.5, 1), (610.5, 2), (732.5, 3), (854.5, 4), (976.5, 5), (1099, 6)],
                   ycal=[(395, 0.30), (491, 0.25), (587.5, 0.20), (683.5, 0.15), (780.5, 0.10), (876.5, 0.05), (973, 0.0)],
                   exclude=[(848, 1088, 408, 472)]),
    "Z26_5a3": dict(img="Zhang2026_CES_Fig5.png", box=(92, 496, 860, 1197),
                    xcal=[(92, 5), (173, 10), (254.5, 15), (335.5, 20), (416, 25), (496.5, 30)],
                    ycal=[(859.5, 40), (916.5, 35), (972.5, 30), (1028.5, 25), (1085, 20), (1141, 15), (1197, 10)],
                    exclude=[(95, 185, 862, 915)]),
    "Z26_5b3": dict(img="Zhang2026_CES_Fig5.png", box=(616, 1031, 860, 1195),
                    xcal=[(649.5, 60), (736.5, 65), (823.5, 70), (909.5, 75), (996.5, 80)],
                    ycal=[(859.5, 40), (971.5, 30), (1026.5, 25), (1083.5, 20), (1138.5, 15), (1195, 10)],
                    exclude=[(619, 710, 862, 915)]),
    "Z26_5c3": dict(img="Zhang2026_CES_Fig5.png", box=(1155, 1570, 860, 1206),
                    xcal=[(1155, 0.1), (1253.5, 0.2), (1353, 0.3), (1452.5, 0.4), (1550.5, 0.5)],
                    ycal=[(859.5, 40), (917.5, 35), (974.5, 30), (1032.5, 25), (1091, 20), (1147.5, 15), (1206, 10)],
                    exclude=[(1158, 1250, 862, 915)]),
    "Z26_9d": dict(img="Zhang2026_CES_Fig9.png", box=(782, 1400, 567, 1107),
                   xcal=[(867, 10), (973.5, 15), (1293, 30), (1399.5, 35)],
                   ycal=[(566.5, 19.5), (674.5, 19.0), (890.5, 18.0), (1106.5, 17.0)],
                   exclude=[(1015, 1390, 950, 1095)]),
}
# Conditions of the plate-heat-exchanger runs (Zhang et al., 2026, Section 2.1): the abscissa of each marker is
# snapped to the nearest stated condition.
PHE_LEVELS = {"Z26_5a3": ("v_cm_s", [6.87, 13.73, 18.31, 27.46]), "Z26_5b3": ("T_C", [60.0, 70.0, 75.0, 80.0]),
              "Z26_5c3": ("NaOH_wt_pct", [0.125, 0.25, 0.5])}
PHE_NOMINAL = dict(T_C=80.0, v_cm_s=27.46, NaOH_wt_pct=0.5)
PHE = dict(m_wet_g=128.74, water_fraction=0.86, rho_dry_g_cm3=0.14, n_channels=6, W_cm=7.8, L_cm=22.3,
           t_water_flush_min=5.0)          # Sections 2.1 and 3.1 of the source


def calib(pairs):
    px, val = np.array(pairs, float).T
    s, i = np.polyfit(px, val, 1)
    return s, i, float(np.max(np.abs(val - (s * px + i))))


def dark_mask(panel, margin):
    p = PANELS[panel]
    im = np.asarray(Image.open(os.path.join(FIG, p["img"])).convert("RGB")).astype(int)
    m = (im.mean(axis=2) < 90) & ((im.max(axis=2) - im.min(axis=2)) < 50)
    x0, x1, y0, y1 = p["box"]
    out = np.zeros_like(m)
    out[y0 + margin:y1 - margin, x0 + margin:x1 - margin] = m[y0 + margin:y1 - margin, x0 + margin:x1 - margin]
    for (a, b, c, d) in p["exclude"]:
        out[c:d, a:b] = False
    return out


def axes(panel):
    p = PANELS[panel]
    sx, ix, ex = calib(p["xcal"])
    sy, iy, ey = calib(p["ycal"])
    return (lambda px: sx * px + ix), (lambda py: sy * py + iy), dict(panel=panel, image=p["img"], x_units_per_px=sx,
                                                                     x_offset=ix, x_max_abs_resid=ex, y_units_per_px=sy,
                                                                     y_offset=iy, y_max_abs_resid=ey)


def blobs(panel, k, margin=2):
    """Centroids of filled markers: thin lines (frame, error bars, connecting lines, text) are removed by an opening."""
    fx, fy, c = axes(panel)
    m = ndi.binary_opening(dark_mask(panel, margin), structure=np.ones((k, k), bool))
    lab, n = ndi.label(m)
    com = np.asarray(ndi.center_of_mass(m, lab, range(1, n + 1)))
    area = np.asarray(ndi.sum(m, lab, range(1, n + 1)))
    keep = area >= 0.4 * np.median(area)
    pts = sorted((float(fx(cx)), float(fy(cy))) for (cy, cx) in com[keep])
    return pts, c


def lnrate_sd(model, T, v):
    """Standard deviation of ln(rate) from the jackknife covariance of (ln ref, alpha, beta)."""
    g = np.array([1.0, T - cal["T_ref_C"], np.log(v / cal["v_ref_cm_s"])])
    return float(np.sqrt(g @ COV[model] @ g))


def main():
    cals, dig = [], []

    # ================================================================== A. flat channel, 75 degC, 23.65 cm/s
    TA, VA = 75.0, 23.65
    fx, fy, c = axes("Z26_8b")
    cals.append(c)
    ys, xs = np.nonzero(dark_mask("Z26_8b", 9))
    t, h = fx(xs), 10.0 * fy(ys)                        # min, mm
    w = 0.1
    b = np.floor(t / w + 0.5).astype(int)
    rows = [(bi * w, float(np.median(h[b == bi])), int((b == bi).sum())) for bi in np.unique(b) if (b == bi).sum() >= 4]
    cu = pd.DataFrame(rows, columns=["t_min", "value", "n_px"])
    cu = cu[cu.t_min >= 0.05].reset_index(drop=True)
    h0 = float(cu.value.iloc[:2].mean())
    y = np.clip(cu.value.to_numpy() / h0, 0, None)
    tt = cu.t_min.to_numpy()
    for ti, vi, ni in zip(cu.t_min, cu.value, cu.n_px):
        dig.append(dict(panel="Z26_8b", series="T=75,v=23.65", t_or_x=ti, value=vi, unit="thickness_mm vs min", n_px=ni))
    t90, t95 = e16.t_cross(tt, y, 0.10), e16.t_cross(tt, y, 0.05)
    tc, rmse0, _ = e16.fit(e16.m0, [tt[-1]], [0.2 * tt[-1]], [5 * tt[-1]], tt, y)
    k1, rmse1, _ = e16.fit(e16.m1, [3.0 / tt[-1]], [1e-4], [10], tt, y)
    sel = y > 0.25                                       # first stage (as in the published linear fit)
    slope = float(np.polyfit(tt[sel], cu.value.to_numpy()[sel], 1)[0])
    A = dict(source="Zhang et al. (2026), Fig. 8b", T_C=TA, v_cm_s=VA, NaOH_wt_pct=0.5, n_points=int(len(cu)),
             h0_mm=h0, t_end_obs_min=float(tt[-1]), t90_obs_min=t90, t95_obs_min=t95,
             rate_obs_first_stage_mm_min=-slope, rate_published_mm_min=0.5,
             single_curve_rmse_uniform=rmse0, single_curve_rmse_first_order=rmse1,
             outside_calibrated_range="temperature (75 > 70 degC); velocity 23.65 vs 23 cm/s")
    for model in ("M0", "M1"):
        r = float(e16.rate(TA, VA, P[model]))
        t90p = 0.90 * h0 / r if model == "M0" else np.log(10) / r
        sd = lnrate_sd(model, TA, VA)
        cc = dict(id="Z26_8b", T=TA, v=VA, h0=h0, t=tt, y=y)
        yhat = e16.predict(cc, P[model], model)
        A[model] = dict(rate_pred=r, rate_unit="mm/min" if model == "M0" else "1/min", t90_pred_min=float(t90p),
                        t90_ratio_pred_obs=float(t90p / t90), ln_rate_sd_parameters=sd,
                        t90_pred_95ci_parameters=[float(t90p * np.exp(-1.96 * sd)), float(t90p * np.exp(1.96 * sd))],
                        curve_rmse=float(np.sqrt(np.mean((yhat - y) ** 2))), curve_bias=float(np.mean(yhat - y)))
        if model == "M0":
            A[model]["rate_ratio_pred_obs_first_stage"] = r / -slope
        # audit rule at the unseen condition: wash time for CS >= 95% (nominal) and q0.10(CS) >= 95% (U0, U3)
        p = P[model]
        tn = e17.wash_time(model, TA, VA, p)
        t0 = e17.wash_time(model, TA, VA, p, e17.draws(model, e17.M_POLICY, 0, np.random.default_rng(900)))
        t3 = e17.wash_time(model, TA, VA, p, e17.draws(model, e17.M_POLICY, 3, np.random.default_rng(903)))
        chk = {}
        for label, tw in (("nominal", tn), ("U0", t0), ("U3", t3)):
            yo = float(np.interp(tw, tt, y, right=0.0)) if tw <= tt.max() + 1.0 else 0.0
            cso = 100.0 * (1.0 - yo * h0 / e17.H_REF)
            chk[label] = dict(wash_time_min=tw, observed_CS=cso, observed_pass=bool(cso >= e17.FLOOR))
        A[model]["audit_rule_at_unseen_condition"] = chk
    # time at which the measured curve reaches the cleaning floor (CS = 95% with h_ref = 3 mm)
    A["t_obs_CS95_min"] = e16.t_cross(tt, y * h0 / e17.H_REF, 0.05)

    # ================================================================== B. laboratory plate heat exchanger
    phe_rows = []
    for panel, (var, levels) in PHE_LEVELS.items():
        pts, c = blobs(panel, 9)
        cals.append(c)
        assert len(pts) == len(levels), (panel, pts)
        for (xv, yv), lv in zip(pts, levels):
            assert abs(xv - lv) < 0.06 * (max(levels) - min(levels)) + 1e-9, (panel, xv, lv)
            dig.append(dict(panel=panel, series=var, t_or_x=xv, value=yv, unit="t_end_min vs " + var, n_px=np.nan))
            cond = dict(PHE_NOMINAL)
            cond[var] = lv
            phe_rows.append(dict(series=var, **cond, t_end_digitised_min=yv, t_end_min=round(2 * yv) / 2))
    phe = pd.DataFrame(phe_rows)
    rho_wet = PHE["rho_dry_g_cm3"] / (1.0 - PHE["water_fraction"])
    area = PHE["n_channels"] * 2 * PHE["W_cm"] * PHE["L_cm"]                 # cm2, projected plate area (two plates per channel)
    h_mean = 10.0 * PHE["m_wet_g"] / (rho_wet * area)                        # mm
    phe["t_alkaline_obs_min"] = phe.t_end_min - PHE["t_water_flush_min"]
    phe["rate_flat_channel_mm_min"] = e16.rate(phe.T_C, phe.v_cm_s, P["M0"])
    phe["t_uniform_pred_min"] = h_mean / phe.rate_flat_channel_mm_min
    phe["ratio_pred_obs"] = phe.t_uniform_pred_min / phe.t_alkaline_obs_min
    phe["within_model_scope"] = phe.NaOH_wt_pct == 0.5                       # the law was calibrated for 0.5 wt% only
    phe.to_csv(os.path.join(OUT, "E24_plate_heat_exchanger_test.csv"), index=False, float_format="%.5g")

    pts, c = blobs("Z26_9d", 5)
    cals.append(c)
    eff = pd.DataFrame(pts, columns=["t_min", "mass_g"])
    for ti, mi in pts:
        dig.append(dict(panel="Z26_9d", series="effluent protein mass, nominal", t_or_x=ti, value=mi, unit="g vs min", n_px=np.nan))
    m_final = float(eff[eff.t_min >= 20].mass_g.mean())
    frac = eff.mass_g.to_numpy() / m_final

    def t_frac(level):
        i = int(np.where(frac >= level)[0][0])
        if i == 0:
            return float(eff.t_min.iloc[0])
        return float(eff.t_min.iloc[i - 1] + (level - frac[i - 1]) * (eff.t_min.iloc[i] - eff.t_min.iloc[i - 1]) / (frac[i] - frac[i - 1]))

    nom = phe[(phe.series == "v_cm_s") & (phe.v_cm_s == 27.46)].iloc[0]

    def slope_ln(sub, xcol, logx):
        xx = np.log(sub[xcol]) if logx else sub[xcol]
        return float(np.polyfit(xx, np.log(sub.t_alkaline_obs_min), 1)[0])

    B = dict(source="Zhang et al. (2026), Figs. 5 and 9d; laboratory plate heat exchanger, 2 channels x 3 passes",
             wet_density_g_cm3=rho_wet, plate_area_cm2=area, mean_deposit_thickness_mm=h_mean,
             nominal=dict(T_C=80.0, v_cm_s=27.46, NaOH_wt_pct=0.5, t_end_min=float(nom.t_end_min),
                          t_alkaline_obs_min=float(nom.t_alkaline_obs_min), rate_flat_channel_mm_min=float(nom.rate_flat_channel_mm_min),
                          t_uniform_pred_min=float(nom.t_uniform_pred_min), ratio_pred_obs=float(nom.ratio_pred_obs),
                          effluent_final_mass_g=m_final, fraction_removed_at_first_sample=float(frac[0]),
                          t_first_sample_min=float(eff.t_min.iloc[0]),
                          t95_uniform_pred_min=0.95 * float(nom.t_uniform_pred_min), t98_uniform_pred_min=0.98 * float(nom.t_uniform_pred_min),
                          t_alkaline_to_95pct_min=t_frac(0.95) - PHE["t_water_flush_min"],
                          t_alkaline_to_98pct_min=t_frac(0.98) - PHE["t_water_flush_min"]),
             ratio_pred_obs_range_0p5wt=[float(phe[phe.within_model_scope].ratio_pred_obs.min()),
                                         float(phe[phe.within_model_scope].ratio_pred_obs.max())],
             apparent_temperature_coefficient_per_degC=-slope_ln(phe[phe.series == "T_C"], "T_C", False),
             apparent_velocity_exponent=-slope_ln(phe[phe.series == "v_cm_s"], "v_cm_s", True),
             apparent_NaOH_order_0p125_to_0p5=-slope_ln(phe[phe.series == "NaOH_wt_pct"], "NaOH_wt_pct", True),
             calibrated_flat_channel=dict(alpha_per_degC=float(P["M0"][1]), beta=float(P["M0"][2])),
             note="t_end is the time at which the protein mass in the tank first reached its final value; it includes a 5-min "
                  "water flush. Prediction: uniform removal of the mean deposit thickness over the whole plate area at the "
                  "flat-channel rate; the part removed by the water flush is not subtracted (longer predicted time).")

    # ================================================================== C. plateau removal fluxes of other laboratories
    rho_dry = PHE["rho_dry_g_cm3"]                                            # g/cm3 of wet deposit (Zhang et al., 2025, 2026)
    k_flux = rho_dry * 1e4 / 10.0 / 60.0                                      # mm/min -> g dry matter m-2 s-1
    fl = []
    # Gillham et al. (1999), Table 3, isothermal runs (T_block = T_bulk = 50 degC), 6-mm tube, 0.5 wt% NaOH; P in g protein m-2 s-1
    for q_ml, re_, p_obs, tau in ((100, 585, 0.13, 22), (260, 1500, 0.14, 17), (400, 2340, 0.19, 12), (800, 4680, 0.17, 8)):
        v = q_ml / 60.0 / (np.pi * 0.6 ** 2 / 4)                              # cm/s in the clean 6-mm tube
        fl.append(dict(source="Gillham et al. (1999), Table 3", soil="whey-protein fouling deposit, tube", T_C=50.0, v_cm_s=v,
                       Re=re_, flux_obs_g_m2_s=p_obs, basis_obs="protein", total_cleaning_time_obs_min=tau))
    # Xin et al. (2004), Tables 1 and 2: WPC gel (25 wt% solids), 0.5 wt% NaOH; R_m in g gel m-2 s-1
    for T, v, rm in ((35, 0.29, 0.33), (45, 0.24, 0.48), (55, 0.21, 0.84), (65, 0.18, 1.12), (75, 0.16, 2.07)):
        fl.append(dict(source="Xin et al. (2004), Table 1", soil="WPC gel film, tube", T_C=float(T), v_cm_s=100 * v, Re=6080,
                       flux_obs_g_m2_s=0.25 * rm, basis_obs="gel solids (R_m x 0.25)", total_cleaning_time_obs_min=np.nan))
    for v, rm in ((0.09, 0.88), (0.18, 1.21), (0.25, 1.39), (0.37, 1.85), (0.46, 2.07)):
        fl.append(dict(source="Xin et al. (2004), Table 2", soil="WPC gel film, tube", T_C=65.0, v_cm_s=100 * v, Re=np.nan,
                       flux_obs_g_m2_s=0.25 * rm, basis_obs="gel solids (R_m x 0.25)", total_cleaning_time_obs_min=np.nan))
    fl = pd.DataFrame(fl)
    fl["rate_pred_mm_min"] = e16.rate(fl.T_C, fl.v_cm_s, P["M0"])
    fl["flux_pred_g_dry_m2_s"] = k_flux * fl.rate_pred_mm_min
    fl["ratio_pred_obs"] = fl.flux_pred_g_dry_m2_s / fl.flux_obs_g_m2_s
    fl["inside_calibrated_T_and_v"] = fl.T_C.between(*T_CAL) & fl.v_cm_s.between(*V_CAL)
    fl.to_csv(os.path.join(OUT, "E24_plateau_flux_other_laboratories.csv"), index=False, float_format="%.4g")
    C = dict(dry_matter_density_g_cm3=rho_dry,
             by_source={s: dict(n=int(len(g)), ratio_min=float(g.ratio_pred_obs.min()), ratio_median=float(g.ratio_pred_obs.median()),
                                ratio_max=float(g.ratio_pred_obs.max())) for s, g in fl.groupby("source")},
             all=dict(n=int(len(fl)), ratio_min=float(fl.ratio_pred_obs.min()), ratio_median=float(fl.ratio_pred_obs.median()),
                      ratio_max=float(fl.ratio_pred_obs.max()),
                      n_inside_calibrated_range=int(fl.inside_calibrated_T_and_v.sum())))

    # ================================================================== D. published sensitivities
    def ea(alpha):                                                            # kJ/mol, same convention as E16 (50-70 degC)
        return alpha * R_GAS * 323.15 * 343.15 / 1000.0

    x2 = fl[fl.source.str.contains("Table 2")]
    xin_beta = float(np.polyfit(np.log(x2.v_cm_s), np.log(x2.flux_obs_g_m2_s), 1)[0])
    x1 = fl[fl.source.str.contains("Table 1")]
    g = fl[fl.source.str.contains("Gillham")]
    gil_tau = -float(np.polyfit(np.log(g.Re), np.log(g.total_cleaning_time_obs_min), 1)[0])
    gil_p = float(np.polyfit(np.log(g.Re), np.log(g.flux_obs_g_m2_s), 1)[0])
    S = [
        # quantity, source, value, low, high, basis / location
        ("apparent activation energy, kJ/mol", "this work, uniform law (E16)", ea(P["M0"][1]), np.nan, np.nan,
         "calibrated, 50-70 degC; jackknife SE %.0f" % ea(cal["M0"]["jackknife_se"]["alpha"])),
        ("apparent activation energy, kJ/mol", "this work, first-order law (E16)", ea(P["M1"][1]), np.nan, np.nan,
         "calibrated, 50-70 degC; jackknife SE %.0f" % ea(cal["M1"]["jackknife_se"]["alpha"])),
        ("apparent activation energy, kJ/mol", "illustrative case (assumed alpha_T = 0.035 per degC)", ea(0.035), np.nan, np.nan,
         "assumption of the pipe-circuit case"),
        ("apparent activation energy, kJ/mol", "Gillham et al. (1999)", np.nan, 44, 63,
         "plateau rate, Re 585-4680; Fig. 7 caption (44, 51, 63, 50)"),
        ("apparent activation energy, kJ/mol", "Xin et al. (2004)", 41, 38, 41, "uniform stage 41, decay stage 38; Table 3"),
        ("apparent activation energy, kJ/mol", "Tuladhar et al. (2002)", 43, 41, 46,
         "overall cleaning 43, swelling 46, decay 41; Section 'Effect of temperature'"),
        ("velocity (Reynolds) exponent of the rate", "this work, uniform law (E16)", P["M0"][2], np.nan, np.nan,
         "calibrated, 0.5-23 cm/s; jackknife SE %.2f" % cal["M0"]["jackknife_se"]["beta"]),
        ("velocity (Reynolds) exponent of the rate", "this work, first-order law (E16)", P["M1"][2], np.nan, np.nan,
         "calibrated, 0.5-23 cm/s; jackknife SE %.2f" % cal["M1"]["jackknife_se"]["beta"]),
        ("velocity (Reynolds) exponent of the rate", "illustrative case (assumed beta_Q)", 0.45, np.nan, np.nan,
         "assumption of the pipe-circuit case"),
        ("velocity (Reynolds) exponent of the rate", "Gillham et al. (1999)", np.nan, 0.20, 0.35,
         "plateau rate P ~ Re^n, as stated by the authors (p. 132)"),
        ("velocity (Reynolds) exponent of the rate", "Gillham et al. (1999), total cleaning time", gil_tau, np.nan, np.nan,
         "regression of ln(tau) on ln(Re), isothermal runs at 50 degC, Table 3 (this work)"),
        ("velocity (Reynolds) exponent of the rate", "Xin et al. (2004)", xin_beta, np.nan, np.nan,
         "regression of ln(R_m) on ln(v), 0.09-0.46 m/s at 65 degC, Table 2 (this work)"),
        ("velocity (Reynolds) exponent of the rate", "Tuladhar et al. (2002)", np.nan, np.log10(1.2), np.log10(2.0),
         "10-fold increase of velocity (0.03-0.30 m/s) shortened cleaning by factors of 1.2 (22 degC) and 2.0 (50 degC)"),
        ("velocity (Reynolds) exponent of the rate", "Zhang et al. (2026), plate heat exchanger", B["apparent_velocity_exponent"],
         np.nan, np.nan, "regression of ln(alkaline cleaning time) on ln(v), 6.87-27.46 cm/s at 80 degC, Fig. 5a3 (this work)"),
        ("temperature coefficient of the cleaning time, per degC", "this work, uniform law (E16)", P["M0"][1], np.nan, np.nan,
         "calibrated, 50-70 degC"),
        ("temperature coefficient of the cleaning time, per degC", "Zhang et al. (2026), plate heat exchanger",
         B["apparent_temperature_coefficient_per_degC"], np.nan, np.nan,
         "regression of ln(alkaline cleaning time) on T, 60-80 degC at 27.46 cm/s, Fig. 5b3 (this work)"),
        ("order in NaOH concentration", "illustrative case (assumed gamma_NaOH)", 0.6, np.nan, np.nan,
         "monotonic power law, 0.5-2.0 wt%"),
        ("order in NaOH concentration", "Tuladhar et al. (2002)", np.nan, 0.3, 0.4,
         "overall cleaning rate up to 1.0 wt% (Table 1); optimum at 0.5-1.0 wt%; cleaning time at 30 degC: 1060, 900, 840 and "
         "2700 s at 0.3, 0.5, 1.0 and 2.0 wt%"),
        ("order in NaOH concentration", "Zhang et al. (2026), plate heat exchanger", B["apparent_NaOH_order_0p125_to_0p5"], np.nan,
         np.nan, "regression of ln(alkaline cleaning time) on ln(c), 0.125-0.5 wt%, Fig. 5c3 (this work)"),
    ]
    sens = pd.DataFrame(S, columns=["quantity", "source", "value", "low", "high", "basis"])
    sens.to_csv(os.path.join(OUT, "E24_published_sensitivities.csv"), index=False, float_format="%.3g")
    # NaOH: predicted (assumed power law) versus measured change of the cleaning time between 0.5 and 2.0 wt% (Tuladhar, 30 degC)
    D = dict(xin_velocity_exponent=xin_beta, gillham_time_exponent=gil_tau, gillham_plateau_exponent_regression=gil_p,
             xin_Ea_check_kJ_mol=float(-np.polyfit(1.0 / (x1.T_C + 273.15), np.log(x1.flux_obs_g_m2_s), 1)[0] * R_GAS / 1000.0),
             NaOH_time_ratio_2p0_vs_0p5_wt_measured=2700.0 / 900.0, NaOH_time_ratio_2p0_vs_0p5_wt_assumed_power_law=float(4.0 ** -0.6),
             NaOH_time_ratio_2p0_vs_1p0_wt_measured=2700.0 / 840.0)

    pd.DataFrame(dig).to_csv(os.path.join(OUT, "E24_digitised_Zhang2026.csv"), index=False, float_format="%.5g")
    pd.DataFrame(cals).to_csv(os.path.join(OUT, "E24_axis_calibration.csv"), index=False, float_format="%.6g")
    json.dump(dict(A_flat_channel_75C=A, B_plate_heat_exchanger=B, C_plateau_flux=C, D_sensitivities=D),
              open(os.path.join(OUT, "E24_summary.json"), "w"), indent=2)

    pd.set_option("display.width", 250)
    print(pd.DataFrame(cals)[["panel", "x_max_abs_resid", "y_max_abs_resid"]].to_string(index=False))
    print("\nA:", json.dumps(A, indent=1))
    print("\nB:", json.dumps(B, indent=1))
    print(phe.round(3).to_string(index=False))
    print(eff.round(2).T.to_string())
    print("\nC:", json.dumps(C, indent=1))
    print(fl.round(3).to_string(index=False))
    print("\nD:", json.dumps(D, indent=1))
    print(sens.round(3).to_string(index=False))


if __name__ == "__main__":
    main()
