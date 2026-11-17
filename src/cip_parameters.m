% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function P = cip_parameters()
%CIP_PARAMETERS  Central, editable parameter file for the dairy CIP digital twin.
%
%   P = CIP_PARAMETERS() returns a struct P containing ALL constants, bounds and
%   metadata used by the MATLAB-side scripts. The empirical NUMERIC values are
%   re-exported from CIP_MODEL_PARAMS (the codegen-safe single source of truth
%   that the Simulink MATLAB Function blocks also call), guaranteeing that the
%   model and the scripts always use identical coefficients (constraint #11).
%
%   ------------------------------------------------------------------
%   SCIENTIFIC DISCLAIMER
%   ------------------------------------------------------------------
%   The coefficients are INITIAL, PROOF-OF-CONCEPT ASSUMPTIONS chosen to produce
%   physically plausible *synthetic* CIP behaviour. They are NOT calibrated
%   against industrial or peer-reviewed dairy data. Every coefficient MUST be
%   re-estimated from plant data or validated literature before any operational
%   or scientific use. All data produced are SIMULATION-GENERATED SYNTHETIC DATA.
%   ------------------------------------------------------------------
%
%   See also: CIP_MODEL_PARAMS, RUN_CIP_SCENARIOS, OPTIMIZE_CIP_PARETO.

% ======================================================================
% 1. NUMERIC EMPIRICAL CONSTANTS (single source: cip_model_params.m)
%    Includes all kinetics, COD, thermal, pump, emission, hygiene and EHPI
%    normalization constants, plus T_in_C and numeric helpers.
% ======================================================================
P = cip_model_params();

% ======================================================================
% 2. OPTIMIZATION / SCENARIO METADATA (shared contract for all scripts)
% ======================================================================
% Decision / scenario variables (ORDER IS SIGNIFICANT - used as the x vector).
P.var_names = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final', ...
               'NaOH_pct','soil0','heat_rec','water_rec'};

% Lower / upper bounds, aligned element-by-element with P.var_names.
P.lb = [45,  0.5, 120,  300, 120, 180, 0.5, 0.1, 0.0, 0.0];
P.ub = [85,  3.0, 600, 1800, 600, 900, 2.5, 1.0, 0.7, 0.6];

% Surrogate-model predictors (the 10 scenario variables) and targets.
% hygienic_risk is included so a surrogate is trained for it: this lets the
% AI supervisory safety gate enforce a max_hygienic_risk constraint numerically
% (instead of treating it as merely informative). It is a CONSTRAINT target,
% not one of the Pareto objectives in optimize_cip_pareto (which keeps its 5
% objectives water/energy/COD/CO2/-cleaning unchanged).
P.predictors = P.var_names;
P.targets    = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg', ...
                'cleaning_score','EHPI','hygienic_risk'};

% Targets whose surrogate accuracy is SAFETY-CRITICAL for the supervisory gate.
% A recommended recipe is downgraded to research_only if any of these has a
% held-out R^2 below P.surrogate_r2_floor in results/surrogate_metrics.csv.
P.critical_targets   = {'cleaning_score','COD_mgL','water_L', ...
                        'total_energy_kWh','CO2eq_kg'};
P.surrogate_r2_floor = 0.90;   % [-] minimum acceptable held-out R^2

% Operational decision variables (operator-controllable). soil0 is an
% UNCERTAINTY condition, not an operator setpoint (see optimize_cip_pareto).
P.operational_vars = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final', ...
                      'NaOH_pct','heat_rec','water_rec'};

% Names of all signals logged to logsout by the Simulink model.
P.logged_signals = {'soil','water_L','thermal_energy_kWh','pump_energy_kWh', ...
                    'COD_mgL','NaOH_residual_mgL','CO2eq_kg', ...
                    'cleaning_score','hygienic_risk','EHPI','phase_id'};

% Model name (without extension) and default solver settings.
P.model_name      = 'dairy_cip_digital_twin';
P.solver          = 'ode23t';   % robust for mildly stiff first-order decay
P.max_step_factor = 0.02;       % MaxStep = max_step_factor * stopTime (capped)
P.max_step_cap    = 5;          % [s] absolute cap on MaxStep

% Default scenario values (used as model-workspace defaults so the model runs
% standalone; overridden per run by Simulink.SimulationInput.setVariable).
P.defaults = struct('T_C',65,'Q_m3h',1.5,'t_pre',300,'t_alk',900, ...
                    't_int',300,'t_final',400,'NaOH_pct',1.5,'soil0',0.6, ...
                    'heat_rec',0.3,'water_rec',0.2,'T_in_C',P.T_in_C);
end
