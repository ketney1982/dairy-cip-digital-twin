# Author: Ketney Otto
# Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
#              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
# Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

"""Closed-form implementation of the lumped four-phase dairy CIP simulator.

The Simulink model (dairy_cip_digital_twin.slx) integrates dS/dt = -k_phase(t) S
with piecewise-constant phase rates. Because k_phase is constant within each
phase, the ODE has the exact solution

    S(t_end) = s0 * exp(-(k_pre t_pre + k_alk t_alk + k_rinse (t_int + t_final)))

and every other output is an integral of a piecewise-constant rate. This module
reproduces those outputs exactly (parameters from src/cip_model_params.m) and is
used for (i) verification against the 5,000 Simulink scenarios, (ii) timing,
and (iii) direct Monte Carlo auditing under extended uncertainty.
"""
import numpy as np

P = dict(
    k_cal=0.08, k_pre_base=0.03, k_alk_base=0.01, k_rinse_base=0.006,
    T_ref=60.0, alpha_T=0.035, beta_Q=0.45, gamma_NaOH=0.6, Q_ref=1.5, NaOH_ref=1.0,
    COD_factor=45.0, rho=1000.0, cp=4.186, eta_heater=0.85, deltaP=180000.0,
    eta_pump=0.6, EF_el=0.25, EF_th=0.20, norm_water=500.0, norm_energy=20.0,
    norm_COD=5000.0, norm_CO2=10.0, lam=0.25, T_in=15.0, s_risk=0.05,
)

VARS = ["T_C", "Q_m3h", "t_pre", "t_alk", "t_int", "t_final", "NaOH_pct",
        "soil0", "heat_rec", "water_rec"]
LB = np.array([45, 0.5, 120, 300, 120, 180, 0.5, 0.1, 0.0, 0.0])
UB = np.array([85, 3.0, 600, 1800, 600, 900, 2.5, 1.0, 0.7, 0.6])
OPS = [v for v in VARS if v != "soil0"]


def simulate(T, Q, t_pre, t_alk, t_int, t_final, naoh, s0, eta_heat, eta_water,
             T_in=None, k_cal=None, alpha_T=None, beta_Q=None, gamma=None,
             k_pre_base=None, k_alk_base=None, k_rinse_base=None):
    """Vectorised closed-form CIP cycle. Optional arguments override parameters
    (used for epistemic / disturbance uncertainty in the Monte Carlo audit)."""
    p = P
    T_in = p["T_in"] if T_in is None else T_in
    k_cal = p["k_cal"] if k_cal is None else k_cal
    alpha_T = p["alpha_T"] if alpha_T is None else alpha_T
    beta_Q = p["beta_Q"] if beta_Q is None else beta_Q
    gamma = p["gamma_NaOH"] if gamma is None else gamma
    kpb = p["k_pre_base"] if k_pre_base is None else k_pre_base
    kab = p["k_alk_base"] if k_alk_base is None else k_alk_base
    krb = p["k_rinse_base"] if k_rinse_base is None else k_rinse_base

    fQ = (np.asarray(Q) / p["Q_ref"]) ** beta_Q
    k_pre = k_cal * kpb * fQ
    k_alk = (k_cal * kab * np.exp(alpha_T * (np.asarray(T) - p["T_ref"])) * fQ
             * (np.asarray(naoh) / p["NaOH_ref"]) ** gamma)
    k_rin = k_cal * krb * fQ
    expo = k_pre * t_pre + k_alk * t_alk + k_rin * (np.asarray(t_int) + t_final)
    S_end = np.asarray(s0) * np.exp(-expo)

    t_act = np.asarray(t_pre) + t_alk + t_int + t_final
    water = np.asarray(Q) * 1000.0 / 3600.0 * (1.0 - np.asarray(eta_water)) * t_act
    thermal_kW = (p["rho"] * (np.asarray(Q) / 3600.0) * p["cp"]
                  * np.maximum(np.asarray(T) - T_in, 0.0) / p["eta_heater"]
                  * (1.0 - np.asarray(eta_heat)))
    E_th = thermal_kW * np.asarray(t_alk) / 3600.0
    pump_kW = p["deltaP"] * (np.asarray(Q) / 3600.0) / p["eta_pump"] / 1000.0
    E_p = pump_kW * t_act / 3600.0
    E_tot = E_th + E_p
    COD = p["COD_factor"] * np.maximum(np.asarray(s0) - S_end, 0.0)
    CF = p["EF_th"] * E_th + p["EF_el"] * E_p
    CS = np.clip(100.0 * (1.0 - S_end), 0.0, 100.0)
    R = np.clip(S_end / p["s_risk"], 0.0, 1.0)
    RP = water / p["norm_water"] + E_tot / p["norm_energy"] + COD / p["norm_COD"] + CF / p["norm_CO2"]
    EHPI = CS / (1.0 + p["lam"] * RP)
    return dict(S_end=S_end, water_L=water, thermal_energy_kWh=E_th,
                pump_energy_kWh=E_p, total_energy_kWh=E_tot, COD_mgL=COD,
                CO2eq_kg=CF, cleaning_score=CS, hygienic_risk=R, EHPI=EHPI,
                exponent=expo)


def simulate_X(X, **kw):
    X = np.atleast_2d(X)
    return simulate(*[X[:, i] for i in range(10)], **kw)


def matlab_rand(seed, n_rows, n_cols):
    """Reproduce MATLAB rng(seed); rand(n_rows,n_cols) (Mersenne twister,
    column-major filling)."""
    rs = np.random.RandomState(seed)
    return rs.random_sample(n_rows * n_cols).reshape(n_cols, n_rows).T


def src(name):
    """Locate an input file in data/ or results/ of the repository."""
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (os.path.join(here, "..", "results"), os.path.join(here, "..", "data")):
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(name)
