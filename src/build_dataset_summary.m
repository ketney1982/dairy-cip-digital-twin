% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% BUILD_DATASET_SUMMARY  Compact JSON summary of the synthetic dataset.
%
%   Produces results/dataset_summary.json containing dataset size, per-variable
%   descriptive statistics, a correlation matrix, and a set of named key
%   correlations. This compact summary (NOT the raw data) is what the Gemini
%   plausibility auditor inspects, keeping the prompt small and bounded.
%
%   The dataset is SIMULATION-GENERATED SYNTHETIC DATA.
%
%   See also: GEMINI_PLAUSIBILITY_AUDITOR, VALIDATE_OUTPUTS.

%% ----- Paths ----------------------------------------------------------------
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);

% Default to the canonical synthetic dataset. The optional CIP_DATASET_CSV env
% var lets a driver (run_ai_closed_loop_study) summarize the COMBINED base +
% AI-designed dataset, so the AI hypothesis/audit context reflects the
% accumulated closed-loop feedback rather than only the base dataset.
csvPath  = fullfile(root,'data','dairy_cip_synthetic_dataset.csv');
envCsv   = getenv('CIP_DATASET_CSV');
if ~isempty(envCsv) && exist(envCsv,'file')==2
    csvPath = envCsv;
    fprintf('[build_dataset_summary] Using dataset from CIP_DATASET_CSV: %s\n', csvPath);
end
resDir   = fullfile(root,'results');
if ~exist(resDir,'dir'); mkdir(resDir); end
jsonPath = fullfile(resDir,'dataset_summary.json');

if exist(csvPath,'file') ~= 2
    error('build_dataset_summary:noData','Dataset not found:\n  %s', csvPath);
end

%% ----- Load successful rows -------------------------------------------------
T = readtable(csvPath);
% Solver status (numerical success). Backward-compatible fallback to the legacy
% simulation_status column for older datasets.
if ismember('solver_status', T.Properties.VariableNames)
    solver = string(T.solver_status);
else
    solver = string(T.simulation_status);
end
Ts = T(solver=="success",:);
nTotal = height(T); nSucc = height(Ts); nFail = nTotal - nSucc;

vars = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final','NaOH_pct','soil0', ...
        'heat_rec','water_rec','water_L','thermal_energy_kWh', ...
        'pump_energy_kWh','total_energy_kWh','COD_mgL','NaOH_residual_mgL', ...
        'COD_chem_equiv_mgL','CO2eq_kg','cleaning_score','hygienic_risk','EHPI'};
vars = vars(ismember(vars, Ts.Properties.VariableNames));

%% ----- Per-variable statistics ----------------------------------------------
summary = struct();
summary.generated_label = 'simulation-generated synthetic data';
summary.disclaimer = 'Not real industrial data. Coefficients are proof-of-concept assumptions requiring calibration.';
[~, srcName, srcExt] = fileparts(csvPath);
summary.source_dataset = [srcName srcExt];   % which dataset this summary describes
summary.n_total          = nTotal;
summary.n_solver_success = nSucc;
summary.n_solver_failed  = nFail;

% Process and quality counts from the new status columns (if present).
if ismember('process_feasible', Ts.Properties.VariableNames)
    pf = Ts.process_feasible;
    if ~islogical(pf)
        if isnumeric(pf); pf = pf~=0;
        else; s = lower(strtrim(string(pf))); pf = (s=="true")|(s=="1"); end
    end
    summary.n_process_feasible = sum(pf);
else
    summary.n_process_feasible = nSucc;   % legacy: all solver-ok rows assumed feasible
end
if ismember('quality_status', Ts.Properties.VariableNames)
    qstat = string(Ts.quality_status);
    summary.n_quality_pass         = sum(qstat=="pass");
    summary.n_below_hygiene_floor  = sum(qstat=="below_hygiene_floor");
else
    summary.n_quality_pass = [];
    summary.n_below_hygiene_floor = [];
end

variables = struct();
M = nan(nSucc, numel(vars));
for k = 1:numel(vars)
    x = Ts.(vars{k}); M(:,k) = x;
    x = x(~ismissing(x));
    s = struct('min',[],'max',[],'mean',[],'std',[]);
    if ~isempty(x)
        s.min  = round(min(x),4);
        s.max  = round(max(x),4);
        s.mean = round(mean(x),4);
        s.std  = round(std(x),4);
    end
    variables.(vars{k}) = s;
end
summary.variables = variables;

%% ----- Correlation matrix ---------------------------------------------------
C = nan(numel(vars));
for a = 1:numel(vars)
    for b = 1:numel(vars)
        C(a,b) = round(localSafeCorr(M(:,a),M(:,b)),3);
    end
end
summary.correlation_order  = vars;
summary.correlation_matrix = C;

%% ----- Named key correlations -----------------------------------------------
kc = struct();
kc.T_C_vs_cleaning_score      = round(localSafeCorr(Ts.T_C,      Ts.cleaning_score),3);
kc.NaOH_pct_vs_cleaning_score = round(localSafeCorr(Ts.NaOH_pct, Ts.cleaning_score),3);
kc.t_alk_vs_cleaning_score    = round(localSafeCorr(Ts.t_alk,    Ts.cleaning_score),3);
kc.water_rec_vs_water_L       = round(localSafeCorr(Ts.water_rec,Ts.water_L),3);
kc.heat_rec_vs_total_energy   = round(localSafeCorr(Ts.heat_rec, Ts.total_energy_kWh),3);
kc.soil0_vs_COD_mgL           = round(localSafeCorr(Ts.soil0,    Ts.COD_mgL),3);
kc.soil0_vs_cleaning_score    = round(localSafeCorr(Ts.soil0,    Ts.cleaning_score),3);
% COD chemistry separation: organic proxy vs NaOH residual (used by auditor).
kc.COD_mgL_vs_NaOH_residual   = round(localColCorr(Ts, 'COD_mgL', 'NaOH_residual_mgL'),3);
kc.soil0_vs_NaOH_residual     = round(localColCorr(Ts, 'soil0', 'NaOH_residual_mgL'),3);
summary.key_correlations = kc;

%% ----- Write JSON -----------------------------------------------------------
txt = jsonencode(summary);
fid = fopen(jsonPath,'w');
if fid < 0; error('build_dataset_summary:fopen','Cannot write %s', jsonPath); end
fwrite(fid, txt, 'char');
fclose(fid);

fprintf('[build_dataset_summary] Wrote summary (%d success rows) -> %s\n', nSucc, jsonPath);

%% ===== Local functions ======================================================
function r = localSafeCorr(x, y)
    x = x(:); y = y(:);
    ok = ~ismissing(x) & ~ismissing(y);
    x = x(ok); y = y(ok);
    if numel(x) < 3 || std(x)==0 || std(y)==0; r = NaN; return; end
    r = corr(x, y);
end

function r = localColCorr(T, a, b)
    if ~ismember(a, T.Properties.VariableNames) || ~ismember(b, T.Properties.VariableNames)
        r = NaN; return;
    end
    r = localSafeCorr(T.(a), T.(b));
end
