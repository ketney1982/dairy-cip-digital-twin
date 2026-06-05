% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function M = cip_model_params() %#codegen
%CIP_MODEL_PARAMS  Codegen-safe NUMERIC empirical constants for the CIP twin.
%
%   M = CIP_MODEL_PARAMS() returns a struct of SCALAR numeric constants only,
%   so it can be called from inside Simulink MATLAB Function blocks (which
%   generate code and cannot handle the cell-array metadata in cip_parameters).
%
%   THIS IS THE SINGLE SOURCE OF TRUTH for every empirical NUMBER in the model
%   (constraint: all empirical coefficients centralized in one editable file).
%   cip_parameters.m re-exports these same values for the MATLAB-side scripts.
%
%   >>> All values are INITIAL PROOF-OF-CONCEPT ASSUMPTIONS, not calibrated. <<<
%   They must be re-estimated from plant/literature data before any real use.
%   All data produced with them are SIMULATION-GENERATED SYNTHETIC DATA.

% --- Soil-removal kinetics (first-order, per phase) ---
% k_cal is a single, transparent CALIBRATION factor applied identically to all
% three base rate constants inside cip_core. The spec's literal base rates
% (0.030/0.010/0.006 per second) combined with phase durations of hundreds to
% thousands of seconds drive the decay exponent k*t to ~13-27, which annihilates
% soil in EVERY scenario and saturates cleaning_score at 100 (std ~1e-4) - the
% "model too easy" degenerate case that validate_outputs is designed to catch
% and that would collapse the cleaning-vs-environment Pareto trade-off.
% k_cal = 0.08 was chosen by analytic Monte-Carlo so that cleaning_score spans a
% meaningful range (mean ~94, std ~6, ~60% of scenarios meeting the 95% floor),
% making the hygiene constraint actually bind. It preserves the EXACT equation
% structure and the spec'd RATIOS between the three phase rates. This is a
% proof-of-concept calibration knob and must be re-estimated from plant data.
M.k_cal        = 0.08;    % [-] global kinetic calibration factor (see note above)
M.k_pre_base   = 0.030;   % [1/s] base rate, pre-rinse        (spec value)
M.k_alk_base   = 0.010;   % [1/s] base rate, alkaline wash    (spec value)
M.k_rinse_base = 0.006;   % [1/s] base rate, rinsing          (spec value)
M.T_ref        = 60;      % [degC] reference temperature
M.alpha_T      = 0.035;   % [1/degC] temperature sensitivity
M.beta_Q       = 0.45;    % [-] flow exponent
M.gamma_NaOH   = 0.60;    % [-] NaOH exponent
M.Q_ref        = 1.5;     % [m3/h] reference flow
M.NaOH_ref     = 1.0;     % [%] reference NaOH concentration

% --- Wastewater / COD ---
M.COD_factor          = 45;     % [mg/L per unit cumulative soil removed]
M.COD_chemical_factor = 0.15;   % [-] reported NaOH-residual COD-equivalent only

% --- Thermal energy ---
M.rho        = 1000;      % [kg/m3]
M.cp         = 4.186;     % [kJ/(kg*degC)]
M.eta_heater = 0.85;      % [-]

% --- Pump energy ---
M.deltaP   = 180000;      % [Pa]
M.eta_pump = 0.60;        % [-]

% --- Emission factors ---
M.EF_electricity = 0.25;  % [kg CO2eq/kWh]
M.EF_thermal     = 0.20;  % [kg CO2eq/kWh]

% --- Hygiene constraints ---
M.min_cleaning_score = 95;   % [%]
M.max_hygienic_risk  = 1.0;  % [-]

% --- EHPI normalization ---
M.norm_water_L    = 500;   % [L]
M.norm_energy_kWh = 20;    % [kWh]
M.norm_COD_mgL    = 5000;  % [mg/L]
M.norm_CO2eq_kg   = 10;    % [kg]

% --- Fixed condition ---
M.T_in_C = 15;            % [degC] inlet water temperature

% --- Numeric helpers used inside the model ---
M.soil_risk_ref = 0.05;   % [-] residual-soil scale for hygienic_risk
M.eps_time      = 1e-6;   % [s] floor on elapsed time for averaging
end
