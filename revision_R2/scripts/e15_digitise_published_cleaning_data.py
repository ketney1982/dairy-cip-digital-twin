# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""E15 - Digitisation of published experimental cleaning curves (revision R2).

Sources (both open access, CC BY 4.0; images in ../source_data/published_figures):
  Zhang et al. (2025) J. Food Eng. 400, 112636  - Figs. 6, 9 and 11
  Wiese et al. (2024) Heat Mass Transfer 60, 829-840 - Fig. 10a

Method: every axis is calibrated by linear regression on the pixel positions of its
tick/grid lines (listed below, detected on the native-resolution images); the data
series are separated by colour. Isolated markers (Figs. 9, 11 and Wiese 10a) are
located as centroids of connected components; dense overlapping markers (Fig. 6) are
reduced to the median ordinate per time bin. No point is picked by hand.

Output: ../outputs/E15_digitised_curves.csv, E15_axis_calibration.csv,
        E15_published_scalar_observations.csv
"""
import os
import numpy as np
import pandas as pd
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
FIG = os.path.join(HERE, "..", "source_data", "published_figures")
OUT = os.path.join(HERE, "..", "outputs")

BLUE, NAVY, SKY, CYAN = (0, 0, 255), (0, 0, 160), (0, 160, 255), (0, 240, 255)
RED, TAN, PINK, PURPLE, GREEN, ORANGE = (255, 0, 0), (222, 160, 95), (255, 50, 150), (150, 0, 220), (0, 255, 0), (255, 170, 0)

# Axis calibration tables: (pixel, value) pairs read from frame, tick and grid lines.
PANELS = {
    # ---------------- Zhang et al. (2025), Fig. 6: thickness (mm) vs time (min)
    "Z6a": dict(img="Zhang2025_JFE_Fig6.png", box=(82, 715, 11, 667),
                xcal=[(80, 0), (159.5, 2), (239, 4), (318.5, 6), (398, 8), (477.5, 10), (557, 12), (636.5, 14), (716, 16)],
                ycal=[(9, 3), (119, 2.5), (228.5, 2), (339, 1.5), (449, 1), (558.5, 0.5), (668.5, 0)],
                legend=(455, 702, 22, 200), label=(90, 170, 15, 70)),
    "Z6b": dict(img="Zhang2025_JFE_Fig6.png", box=(794, 1427, 11, 667),
                xcal=[(792, 0), (909.5, 5), (1027.5, 10), (1145, 15), (1263, 20), (1381, 25)],
                ycal=[(9, 3), (119, 2.5), (228.5, 2), (339, 1.5), (449, 1), (558.5, 0.5), (668.5, 0)],
                legend=(1189, 1414, 22, 314), label=(805, 890, 15, 70)),
    "Z6c": dict(img="Zhang2025_JFE_Fig6.png", box=(1505, 2139, 11, 667),
                xcal=[(1503, 0), (1609, 10), (1715, 20), (1821, 30), (1927.5, 40), (2034, 50), (2140, 60)],
                ycal=[(9, 3), (119, 2.5), (228.5, 2), (339, 1.5), (449, 1), (558.5, 0.5), (668.5, 0)],
                legend=(1866, 2126, 22, 200), label=(1515, 1600, 15, 70)),
    # ---------------- Zhang et al. (2025), Fig. 9: protein concentration (g/L) vs time (min), 70 degC
    "Z9a": dict(img="Zhang2025_JFE_Fig9.png", box=(92, 902, 4, 654),
                xcal=[(99, 0), (232, 5), (364.5, 10), (497.5, 15), (630, 20), (762.5, 25), (895, 30)],
                ycal=[(10, 0.7), (101, 0.6), (191.5, 0.5), (282.5, 0.4), (374, 0.3), (464.5, 0.2), (555.5, 0.1), (647, 0)],
                legend=(640, 865, 472, 620), label=(105, 170, 20, 70)),
    "Z9b": dict(img="Zhang2025_JFE_Fig9.png", box=(1017, 1828, 4, 654),
                xcal=[(1024, 0), (1156.5, 5), (1289.5, 10), (1422.5, 15), (1555.5, 20), (1688, 25), (1821, 30)],
                ycal=[(68, 2), (212.5, 1.5), (357.5, 1), (502, 0.5), (647, 0)],
                legend=(1575, 1800, 18, 162), label=(1030, 1095, 20, 70)),
    # ---------------- Zhang et al. (2025), Fig. 11: concentration (g/L) vs time (min), 70 degC
    "Z11a": dict(img="Zhang2025_JFE_Fig11.png", box=(100, 905, 6, 599),
                 xcal=[(107, 0), (239.5, 5), (370.5, 10), (502.5, 15), (634.5, 20), (766.5, 25), (898, 30)],
                 ycal=[(12, 0.7), (94.5, 0.6), (177.5, 0.5), (260.5, 0.4), (343.5, 0.3), (426.5, 0.2), (509.5, 0.1), (592, 0)],
                 legend=(575, 828, 255, 350), label=(115, 200, 15, 75)),
    "Z11b": dict(img="Zhang2025_JFE_Fig11.png", box=(1020, 1824, 6, 599),
                 xcal=[(1028, 0), (1158.5, 5), (1290.5, 10), (1422, 15), (1553.5, 20), (1685.5, 25), (1817, 30)],
                 ycal=[(12, 2), (157, 1.5), (302.5, 1), (447.5, 0.5), (592, 0)],
                 legend=(1493, 1748, 22, 120), label=(1035, 1110, 15, 75)),
    "Z11c": dict(img="Zhang2025_JFE_Fig11.png", box=(100, 905, 695, 1289),
                 xcal=[(107, 0), (220.5, 5), (333.5, 10), (446.5, 15), (559.5, 20), (672.5, 25), (785, 30), (898, 35)],
                 ycal=[(701, 0.8), (773.5, 0.7), (846.5, 0.6), (919, 0.5), (991.5, 0.4), (1064, 0.3), (1136.5, 0.2), (1209.5, 0.1), (1282, 0)],
                 legend=(575, 828, 944, 1040), label=(115, 200, 705, 765)),
    "Z11d": dict(img="Zhang2025_JFE_Fig11.png", box=(1020, 1824, 695, 1289),
                 xcal=[(1027, 0), (1290.5, 5), (1553.5, 10), (1817, 15)],
                 ycal=[(745.5, 1.2), (835, 1.0), (924.5, 0.8), (1013.5, 0.6), (1103.5, 0.4), (1192.5, 0.2), (1282, 0)],
                 legend=(1487, 1753, 828, 924), label=(1035, 1110, 705, 765)),
    # ---------------- Wiese et al. (2024), Fig. 10a: 0.125 M NaOH, 23.5 degC
    "W10a_protein": dict(img="Wiese2024_HMT_Fig10.png", box=(153, 860, 64, 576),
                         xcal=[(160, 0), (237, 10), (314.5, 20), (391, 30), (468, 40), (545, 50), (621.5, 60), (698.5, 70), (776, 80), (852, 90)],
                         ycal=[(118.5, 0.4), (230.5, 0.3), (343.5, 0.2), (456, 0.1), (568.5, 0.0)],
                         legend=(150, 462, 30, 141), label=(0, 0, 0, 0)),
    "W10a_height": dict(img="Wiese2024_HMT_Fig10.png", box=(153, 860, 64, 576),
                        xcal=[(160, 0), (237, 10), (314.5, 20), (391, 30), (468, 40), (545, 50), (621.5, 60), (698.5, 70), (776, 80), (852, 90)],
                        ycal=[(62.5, 4), (188.5, 3), (315.5, 2), (441.5, 1), (568.5, 0)],
                        legend=(150, 462, 30, 141), label=(0, 0, 0, 0)),
}

# Series: panel, name, colour (or "black"/"grey"), mode, conditions
SERIES = [
    ("Z6a", "x=12cm", NAVY, "dense", dict(T_C=70, v_cm_s=1.0, x_cm=12, quantity="thickness_mm", system="closed")),
    ("Z6a", "x=16cm", BLUE, "dense", dict(T_C=70, v_cm_s=1.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6a", "x=19cm", SKY, "dense", dict(T_C=70, v_cm_s=1.0, x_cm=19, quantity="thickness_mm", system="closed")),
    ("Z6a", "x=22cm", CYAN, "dense", dict(T_C=70, v_cm_s=1.0, x_cm=22, quantity="thickness_mm", system="closed")),
    ("Z6b", "v=23.0", RED, "dense", dict(T_C=70, v_cm_s=23.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6b", "v=12.0", TAN, "dense", dict(T_C=70, v_cm_s=12.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6b", "v=2.0", PINK, "dense", dict(T_C=70, v_cm_s=2.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6b", "v=1.5", PURPLE, "dense", dict(T_C=70, v_cm_s=1.5, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6b", "v=1.0", BLUE, "dense", dict(T_C=70, v_cm_s=1.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6b", "v=0.5", GREEN, "dense", dict(T_C=70, v_cm_s=0.5, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6c", "T=70", BLUE, "dense", dict(T_C=70, v_cm_s=1.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6c", "T=60", ORANGE, "dense", dict(T_C=60, v_cm_s=1.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z6c", "T=50", "black", "dense", dict(T_C=50, v_cm_s=1.0, x_cm=16, quantity="thickness_mm", system="closed")),
    ("Z9a", "v=0.5", GREEN, "dots", dict(T_C=70, v_cm_s=0.5, x_cm=np.nan, quantity="tank_conc_g_L", system="closed")),
    ("Z9a", "v=1.0", BLUE, "dots", dict(T_C=70, v_cm_s=1.0, x_cm=np.nan, quantity="tank_conc_g_L", system="closed")),
    ("Z9a", "v=1.5", PURPLE, "dots", dict(T_C=70, v_cm_s=1.5, x_cm=np.nan, quantity="tank_conc_g_L", system="closed")),
    ("Z9b", "v=0.5", GREEN, "dots", dict(T_C=70, v_cm_s=0.5, x_cm=np.nan, quantity="effluent_conc_g_L", system="open")),
    ("Z9b", "v=1.0", BLUE, "dots", dict(T_C=70, v_cm_s=1.0, x_cm=np.nan, quantity="effluent_conc_g_L", system="open")),
    ("Z9b", "v=1.5", PURPLE, "dots", dict(T_C=70, v_cm_s=1.5, x_cm=np.nan, quantity="effluent_conc_g_L", system="open")),
    ("Z11a", "v=1.0", BLUE, "dots", dict(T_C=70, v_cm_s=1.0, x_cm=np.nan, quantity="tank_conc_g_L", system="closed")),
    ("Z11b", "v=1.0", BLUE, "dots", dict(T_C=70, v_cm_s=1.0, x_cm=np.nan, quantity="effluent_conc_g_L", system="open")),
    ("Z11c", "v=0.5", GREEN, "dots", dict(T_C=70, v_cm_s=0.5, x_cm=np.nan, quantity="tank_conc_g_L", system="closed")),
    ("Z11d", "v=23.0", RED, "dots", dict(T_C=70, v_cm_s=23.0, x_cm=np.nan, quantity="tank_conc_g_L", system="closed")),
    ("W10a_protein", "protein", "black", "dots", dict(T_C=23.5, v_cm_s=8.3, x_cm=np.nan, quantity="protein_conc_gWPIgel_per_Lsol", system="closed")),
    ("W10a_height", "layer_height", "grey", "dense", dict(T_C=23.5, v_cm_s=8.3, x_cm=np.nan, quantity="layer_height_mm", system="closed")),
]
BIN_MIN = {"Z6a": 0.25, "Z6b": 0.25, "Z6c": 0.5, "W10a_height": 1.0}

_cache = {}


def load(name):
    if name not in _cache:
        _cache[name] = np.asarray(Image.open(os.path.join(FIG, name)).convert("RGB")).astype(int)
    return _cache[name]


def calib(pairs):
    px = np.array([p for p, _ in pairs], float)
    val = np.array([v for _, v in pairs], float)
    slope, icpt = np.polyfit(px, val, 1)
    resid = val - (slope * px + icpt)
    return slope, icpt, float(np.max(np.abs(resid)))


def mask_for(im, colour, panel_colours):
    """Pixels closer to `colour` than to any other series colour of the panel (and within tolerance)."""
    if colour == "black":
        return (im.mean(axis=2) < 70) & ((im.max(axis=2) - im.min(axis=2)) < 40)
    if colour == "grey":   # dark-grey squares of Wiese Fig. 10a (layer height)
        g = im.mean(axis=2)
        return (g > 60) & (g < 110) & ((im.max(axis=2) - im.min(axis=2)) < 25)
    d = np.sqrt(((im - np.array(colour)) ** 2).sum(axis=2))
    m = d < 70
    for other in panel_colours:
        if isinstance(other, tuple) and other != colour:
            m &= d < np.sqrt(((im - np.array(other)) ** 2).sum(axis=2))
    return m


def restrict(m, box, legend, label, inner=3):
    x0, x1, y0, y1 = box
    out = np.zeros_like(m)
    out[y0 + inner:y1 - inner, x0 + inner:x1 - inner] = m[y0 + inner:y1 - inner, x0 + inner:x1 - inner]
    for (a, b, c, d) in (legend, label):
        out[c:d, a:b] = False
    return out


def main():
    rows, cal_rows = [], []
    for pname, p in PANELS.items():
        sx, ix, ex = calib(p["xcal"])
        sy, iy, ey = calib(p["ycal"])
        cal_rows.append(dict(panel=pname, image=p["img"], x_units_per_px=sx, x_offset=ix, x_max_abs_resid=ex,
                             y_units_per_px=sy, y_offset=iy, y_max_abs_resid=ey,
                             n_x_ticks=len(p["xcal"]), n_y_ticks=len(p["ycal"])))
    cal = {r["panel"]: r for r in cal_rows}

    for pname, sname, colour, mode, cond in SERIES:
        p = PANELS[pname]
        im = load(p["img"])
        panel_colours = [c for (pn, _, c, _, _) in SERIES if pn == pname]
        m = restrict(mask_for(im, colour, panel_colours), p["box"], p["legend"], p["label"])
        c = cal[pname]
        fx = lambda px: c["x_units_per_px"] * px + c["x_offset"]
        fy = lambda py: c["y_units_per_px"] * py + c["y_offset"]
        if mode == "dots":
            if colour == "black":   # remove thin lines (frame, vertical markers): keep blobs only
                m = ndi.binary_opening(m, structure=np.ones((7, 7), bool))
            lab, k = ndi.label(m)
            if k == 0:
                continue
            idx = range(1, k + 1)
            area = np.asarray(ndi.sum(m, lab, idx))
            com = np.asarray(ndi.center_of_mass(m, lab, idx))
            med = np.median(area[area > 20])
            for a, (cy, cx) in zip(area, com):
                if a < 0.25 * med:
                    continue
                n_markers = max(1, int(round(a / med)))   # merged neighbours are flagged
                rows.append(dict(panel=pname, series=sname, **cond, t_min=fx(cx), value=fy(cy),
                                 n_px=int(a), flag="merged" if n_markers > 1 else ("partial" if a < 0.6 * med else "")))
        else:
            if colour in ("black", "grey"):   # remove frame, tick and marker lines: keep marker blobs only
                k = 3 if colour == "black" else 5
                m = ndi.binary_opening(m, structure=np.ones((k, k), bool))
                m[:, p["box"][1] - 8:] = False
            ys, xs = np.nonzero(m)
            if len(xs) == 0:
                continue
            t = fx(xs)
            v = fy(ys)
            w = BIN_MIN[pname]
            b = np.floor(t / w + 0.5).astype(int)
            for bi in np.unique(b):
                sel = b == bi
                if sel.sum() < 12:
                    continue
                rows.append(dict(panel=pname, series=sname, **cond, t_min=bi * w, value=float(np.median(v[sel])),
                                 n_px=int(sel.sum()), flag=""))
            # black/grey series end at their first gap of more than three empty bins (residual line pixels are discarded)
            if colour not in ("black", "grey"):
                continue
            mine = [r for r in rows if r["panel"] == pname and r["series"] == sname]
            others = [r for r in rows if not (r["panel"] == pname and r["series"] == sname)]
            mine.sort(key=lambda r: r["t_min"])
            keep = [mine[0]] if mine else []
            for r in mine[1:]:
                if r["t_min"] - keep[-1]["t_min"] > 3.5 * w:
                    break
                keep.append(r)
            rows[:] = others + keep
    df = pd.DataFrame(rows).sort_values(["panel", "series", "t_min"]).reset_index(drop=True)
    df["source"] = np.where(df.panel.str.startswith("Z"), "Zhang et al. (2025) J Food Eng 400:112636",
                            "Wiese et al. (2024) Heat Mass Transfer 60:829-840")
    df["NaOH_wt_pct"] = 0.5
    df.to_csv(os.path.join(OUT, "E15_digitised_curves.csv"), index=False, float_format="%.5g")
    pd.DataFrame(cal_rows).to_csv(os.path.join(OUT, "E15_axis_calibration.csv"), index=False, float_format="%.6g")

    scal = [
        ("Zhang2025", "Section 2.3", "NaOH concentration of the cleaning solution", 0.5, "wt%", "all runs"),
        ("Zhang2025", "Section 3.1", "initial fouling-layer thickness h0, mean", 2.44, "mm", "32 experiments (SD 0.045 as reported)"),
        ("Zhang2025", "Section 2.2", "initial fouling-layer thickness, range of the average", 2.0, "mm", "lower value of '2 and 3 mm'"),
        ("Zhang2025", "Section 2.2", "initial fouling-layer thickness, range of the average", 3.0, "mm", "upper value of '2 and 3 mm'"),
        ("Zhang2025", "Section 3.1", "thickness at the transition to the second stage, mean", 0.94, "mm", "32 experiments"),
        ("Zhang2025", "Section 3.1", "first stage as share of total cleaning time", 79, "%", "32 experiments"),
        ("Zhang2025", "Section 3.1", "second-stage / first-stage removal-rate ratio", 2.86, "-", "SD 0.81"),
        ("Zhang2025", "Abstract", "total cleaning time at Re 5500 (23 cm/s) and 70 degC", 5.8, "min", ""),
        ("Zhang2025", "Section 3.1", "cleaning time at x = 12 cm, 1 cm/s, 70 degC", 12.2, "min", ""),
        ("Zhang2025", "Section 3.1", "cleaning time at x = 22 cm, 1 cm/s, 70 degC", 16.8, "min", ""),
        ("Zhang2025", "Section 3.1", "thickness removed by a 10-min water flush at 80 degC and 23 cm/s", 0.3, "mm", "no NaOH; 'results not shown' in the source"),
        ("Zhang2025", "Section 2.2", "moisture content of the wet deposit", 86, "wt%", "SD 2.79"),
        ("Wiese2024", "Section 2.3", "NaOH concentration", 0.125, "mol/L", "= 0.5 wt%"),
        ("Wiese2024", "Section 3.3", "temperature of the run in Fig. 10", 23.5, "degC", "SD 1.7"),
        ("Wiese2024", "Section 3.3", "flow velocity at start of the run in Fig. 10", 0.096, "m/s", "Re 1200"),
        ("Wiese2024", "Section 3.3", "flow velocity at end of the run in Fig. 10", 0.07, "m/s", "Re 1000"),
        ("Wiese2024", "Section 3.3", "cleaning duration (99.9% of maximum protein concentration)", 83, "min", ""),
        ("Wiese2024", "Section 3.3", "cleaning duration from layer height (side view)", 69, "min", ""),
        ("Wiese2024", "Section 3.4", "share of soil removed by the flow after 4.5 min", 7.4, "%", ""),
        ("Wiese2024", "Section 2.1", "initial gel-layer thickness", 3.0, "mm", "15% (w/w) WPI gel"),
    ]
    pd.DataFrame(scal, columns=["source", "location", "observation", "value", "unit", "note"]).to_csv(
        os.path.join(OUT, "E15_published_scalar_observations.csv"), index=False)

    print(pd.DataFrame(cal_rows)[["panel", "x_max_abs_resid", "y_max_abs_resid"]].to_string(index=False))
    summ = df.groupby(["panel", "series"]).agg(n=("value", "size"), t0=("t_min", "min"), t1=("t_min", "max"),
                                                 v_first=("value", "first"), v_max=("value", "max"), v_last=("value", "last"),
                                                 flagged=("flag", lambda s: int((s != "").sum())))
    print(summ.to_string())


if __name__ == "__main__":
    main()
