% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% VALIDATE_OUTPUTS  Validate the synthetic dairy-CIP dataset.
%
%   Loads data/dairy_cip_synthetic_dataset.csv, removes failed simulations,
%   checks for missing values and physical plausibility, computes summary
%   statistics and a correlation matrix, raises domain warnings, and writes a
%   human-readable report to results/dataset_validation_report.txt.
%
%   NOTE: The dataset is SIMULATION-GENERATED SYNTHETIC DATA. These checks
%   verify internal consistency of the simulator, NOT agreement with reality.
%
%   See also: RUN_CIP_SCENARIOS, BUILD_DATASET_SUMMARY.

%% ----- Paths ----------------------------------------------------------------
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
csvPath = fullfile(root,'data','dairy_cip_synthetic_dataset.csv');
resDir  = fullfile(root,'results');
if ~exist(resDir,'dir'); mkdir(resDir); end
repPath = fullfile(resDir,'dataset_validation_report.txt');

% Portable, project-relative source path for the published report so the
% generated artifact never embeds a machine-specific absolute path.
srcRel = csvPath;
if startsWith(srcRel,[root filesep]); srcRel = extractAfter(srcRel,[root filesep]); end
srcRel = strrep(srcRel,'\','/');

if exist(csvPath,'file') ~= 2
    error('validate_outputs:noData','Dataset not found:\n  %s\nRun run_cip_scenarios first.', csvPath);
end

%% ----- Load and split (solver status vs process/quality status) -------------
T = readtable(csvPath);
% Solver status = pure NUMERICAL simulation outcome. Backward-compatible: fall
% back to the legacy simulation_status column for older datasets.
if ismember('solver_status', T.Properties.VariableNames)
    solver = string(T.solver_status);
else
    solver = string(T.simulation_status);
end
isSolverOk  = solver == "success";
Ts = T(isSolverOk,:);             % solver-success rows (analysis subset)
nTotal      = height(T);
nSolverOk   = height(Ts);
nSolverFail = nTotal - nSolverOk;
solverFailFrac = nSolverFail / max(1,nTotal);

% PROCESS feasibility and HYGIENE quality among solver-success rows. These are
% deliberately SEPARATE from solver success: a converged simulation can still be
% process-infeasible or below the hygiene floor, and that must not be read as a
% failed (or successful) solve.
procFeas  = localProcessFeasible(Ts);
nFeasible = sum(procFeas);
if ismember('quality_status', Ts.Properties.VariableNames)
    qstat = string(Ts.quality_status);
else
    qstat = strings(nSolverOk,1);
end
nQualPass   = sum(qstat=="pass");
nQualFloor  = sum(qstat=="below_hygiene_floor");
nQualInfeas = sum(qstat=="infeasible");

%% ----- Variables of interest ------------------------------------------------
inputVars  = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final','NaOH_pct', ...
              'soil0','heat_rec','water_rec'};
outputVars = {'water_L','thermal_energy_kWh','pump_energy_kWh', ...
              'total_energy_kWh','COD_mgL','NaOH_residual_mgL','CO2eq_kg', ...
              'cleaning_score','hygienic_risk','EHPI'};
allVars = [inputVars, outputVars];
allVars = allVars(ismember(allVars, Ts.Properties.VariableNames));

%% ----- Missing values -------------------------------------------------------
missCount = zeros(1,numel(allVars));
for k = 1:numel(allVars)
    missCount(k) = sum(ismissing(Ts.(allVars{k})));
end

%% ----- Physical plausibility ------------------------------------------------
checks = {};
checks(end+1,:) = {'water_L >= 0',            localCountViol(Ts,'water_L', @(x) x < 0)};
checks(end+1,:) = {'thermal_energy_kWh >= 0', localCountViol(Ts,'thermal_energy_kWh', @(x) x < 0)};
checks(end+1,:) = {'pump_energy_kWh >= 0',    localCountViol(Ts,'pump_energy_kWh', @(x) x < 0)};
checks(end+1,:) = {'total_energy_kWh >= 0',   localCountViol(Ts,'total_energy_kWh', @(x) x < 0)};
checks(end+1,:) = {'COD_mgL >= 0',            localCountViol(Ts,'COD_mgL', @(x) x < 0)};
checks(end+1,:) = {'0 <= cleaning_score <=100',localCountViol(Ts,'cleaning_score', @(x) x < 0 | x > 100)};
checks(end+1,:) = {'0 <= hygienic_risk <= 1', localCountViol(Ts,'hygienic_risk', @(x) x < 0 | x > 1)};
checks(end+1,:) = {'EHPI >= 0',               localCountViol(Ts,'EHPI', @(x) x < 0)};

%% ----- Summary statistics ---------------------------------------------------
statNames = {'min','max','mean','std','median'};
S = nan(numel(allVars), numel(statNames));
for k = 1:numel(allVars)
    x = Ts.(allVars{k});
    x = x(~ismissing(x));
    if isempty(x); continue; end
    S(k,:) = [min(x), max(x), mean(x), std(x), median(x)];
end

%% ----- Correlation matrix ---------------------------------------------------
M = nan(nSolverOk, numel(allVars));
for k = 1:numel(allVars); M(:,k) = Ts.(allVars{k}); end
C = localSafeCorrMatrix(M);

%% ----- Domain warnings ------------------------------------------------------
W = strings(0,1);
if solverFailFrac > 0.05
    W(end+1) = sprintf('HIGH SOLVER FAILURE RATE: %.1f%% of simulations failed (>5%%).', 100*solverFailFrac);
end
cs = Ts.cleaning_score; cs = cs(~ismissing(cs));
if ~isempty(cs)
    if mean(cs > 99) > 0.95
        W(end+1) = "MODEL TOO EASY: cleaning_score > 99 in >95% of runs (consider stricter kinetics).";
    end
    if mean(cs < 80) > 0.95
        W(end+1) = "MODEL TOO STRICT: cleaning_score < 80 in >95% of runs (consider faster kinetics).";
    end
end
r_soil_cod  = localSafeCorr(Ts.soil0,     Ts.COD_mgL);
r_wrec_wat  = localSafeCorr(Ts.water_rec, Ts.water_L);
r_hrec_then = localSafeCorr(Ts.heat_rec,  Ts.thermal_energy_kWh);
r_cod_naoh  = localColCorr(Ts, 'COD_mgL', 'NaOH_residual_mgL');

% --- COD modelling correlation tests -------------------------------------
% Organic COD must DEMONSTRABLY track soil removal (clearly positive corr with
% soil0), and must NOT be a near-perfect proxy of NaOH residual (which would mean
% chemical carry-over dominates the organic signal). soil0 must out-correlate NaOH.
if ~isfinite(r_soil_cod) || r_soil_cod < 0.15
    W(end+1) = sprintf(['WEAK COD-SOIL LINK: corr(soil0,COD_mgL)=%.3f (<0.15); ', ...
        'organic COD must clearly track soil removal.'], r_soil_cod);
end
if isfinite(r_cod_naoh) && r_cod_naoh > 0.95
    W(end+1) = sprintf(['COD/NaOH COLLINEARITY: corr(COD_mgL,NaOH_residual_mgL)=%.3f ', ...
        '(>0.95); organic COD is dominated by NaOH residual.'], r_cod_naoh);
end
if isfinite(r_soil_cod) && isfinite(r_cod_naoh) && r_soil_cod <= r_cod_naoh
    W(end+1) = sprintf(['COD PROXY ORDERING: corr(soil0,COD)=%.3f should exceed ', ...
        'corr(NaOH_residual,COD)=%.3f for COD to be an organic proxy.'], r_soil_cod, r_cod_naoh);
end
if ~isfinite(r_wrec_wat) || r_wrec_wat >= -0.05
    W(end+1) = sprintf('WATER RECOVERY ANOMALY: corr(water_rec,water_L)=%.3f (expected clearly negative).', r_wrec_wat);
end
if ~isfinite(r_hrec_then) || r_hrec_then >= -0.05
    W(end+1) = sprintf('HEAT RECOVERY ANOMALY: corr(heat_rec,thermal_energy_kWh)=%.3f (expected clearly negative).', r_hrec_then);
end

%% ----- Write report ---------------------------------------------------------
fid = fopen(repPath,'w');
if fid < 0; error('validate_outputs:fopen','Cannot open report file: %s', repPath); end
cu = onCleanup(@() fclose(fid));

fprintf(fid,'================================================================\n');
fprintf(fid,' DAIRY CIP DIGITAL TWIN - DATASET VALIDATION REPORT\n');
fprintf(fid,' (SIMULATION-GENERATED SYNTHETIC DATA - NOT real measurements)\n');
fprintf(fid,'================================================================\n\n');
fprintf(fid,'Source file : %s\n', srcRel);
fprintf(fid,'Total rows  : %d\n\n', nTotal);

fprintf(fid,'---- SOLVER STATUS (numerical simulation outcome) ----\n');
fprintf(fid,'  solver success : %d (%.2f%%)\n', nSolverOk, 100*(nSolverOk/max(1,nTotal)));
fprintf(fid,'  solver failed  : %d (%.2f%%)\n\n', nSolverFail, 100*solverFailFrac);

fprintf(fid,'---- PROCESS STATUS (among solver-success rows; SEPARATE from solver success) ----\n');
fprintf(fid,'  process_feasible    : %d (%.2f%% of solver-success)\n', nFeasible, 100*(nFeasible/max(1,nSolverOk)));
fprintf(fid,'  quality pass        : %d\n', nQualPass);
fprintf(fid,'  below hygiene floor : %d\n', nQualFloor);
fprintf(fid,'  quality infeasible  : %d\n', nQualInfeas);
fprintf(fid,'  NOTE: cleaning_score and hygienic_risk drive PROCESS quality, NOT the\n');
fprintf(fid,'        numerical solver outcome. The two are reported separately by design.\n\n');

fprintf(fid,'---- MISSING VALUES (solver-success rows) ----\n');
for k = 1:numel(allVars)
    fprintf(fid,'  %-20s : %d\n', allVars{k}, missCount(k));
end
fprintf(fid,'\n');

fprintf(fid,'---- PHYSICAL PLAUSIBILITY CHECKS ----\n');
for k = 1:size(checks,1)
    nv = checks{k,2};
    tag = 'OK'; if nv > 0; tag = 'VIOLATION'; end
    fprintf(fid,'  [%-9s] %-26s violations=%d\n', tag, checks{k,1}, nv);
end
fprintf(fid,'\n');

fprintf(fid,'---- SUMMARY STATISTICS (solver-success rows) ----\n');
fprintf(fid,'  %-20s %12s %12s %12s %12s %12s\n','variable',statNames{:});
for k = 1:numel(allVars)
    fprintf(fid,'  %-20s %12.4g %12.4g %12.4g %12.4g %12.4g\n', allVars{k}, S(k,:));
end
fprintf(fid,'\n');

fprintf(fid,'---- KEY CORRELATIONS ----\n');
fprintf(fid,'  corr(soil0, COD_mgL)               = %.3f  (organic proxy; want > 0.15)\n', r_soil_cod);
fprintf(fid,'  corr(COD_mgL, NaOH_residual_mgL)   = %.3f  (want < 0.95; not NaOH-dominated)\n', r_cod_naoh);
fprintf(fid,'  corr(water_rec, water_L)           = %.3f\n', r_wrec_wat);
fprintf(fid,'  corr(heat_rec, thermal_energy_kWh) = %.3f\n', r_hrec_then);
fprintf(fid,'  corr(T_C, cleaning_score)          = %.3f\n', localSafeCorr(Ts.T_C, Ts.cleaning_score));
fprintf(fid,'  corr(NaOH_pct, cleaning_score)     = %.3f\n', localSafeCorr(Ts.NaOH_pct, Ts.cleaning_score));
fprintf(fid,'  corr(t_alk, cleaning_score)        = %.3f\n', localSafeCorr(Ts.t_alk, Ts.cleaning_score));
fprintf(fid,'\n');

fprintf(fid,'---- WARNINGS ----\n');
if isempty(W)
    fprintf(fid,'  None. Dataset passed all heuristic checks.\n');
else
    for k = 1:numel(W)
        fprintf(fid,'  [!] %s\n', W(k));
    end
end
fprintf(fid,'\n---- FULL CORRELATION MATRIX ----\n   (order: %s)\n', strjoin(allVars,', '));
for r = 1:size(C,1)
    fprintf(fid,'  ');
    fprintf(fid,'%6.2f ', C(r,:));
    fprintf(fid,'\n');
end

clear cu;   % flush/close report

%% ----- Console echo ---------------------------------------------------------
fprintf(['[validate_outputs] rows=%d | solver: ok=%d failed=%d (%.2f%%) | ', ...
         'process_feasible=%d quality_pass=%d\n'], ...
    nTotal, nSolverOk, nSolverFail, 100*solverFailFrac, nFeasible, nQualPass);
if isempty(W)
    fprintf('[validate_outputs] No warnings. Report -> %s\n', repPath);
else
    fprintf('[validate_outputs] %d WARNING(S) raised. See %s\n', numel(W), repPath);
    for k = 1:numel(W); fprintf('   [!] %s\n', W(k)); end
end

%% ===== Local functions ======================================================
function n = localCountViol(T, var, predFcn)
    if ~ismember(var, T.Properties.VariableNames); n = 0; return; end
    x = T.(var); x = x(~ismissing(x));
    n = sum(predFcn(x));
end

function r = localSafeCorr(x, y)
    x = x(:); y = y(:);
    ok = ~ismissing(x) & ~ismissing(y);
    x = x(ok); y = y(ok);
    if numel(x) < 3 || std(x)==0 || std(y)==0
        r = NaN; return;
    end
    r = corr(x, y);
end

function C = localSafeCorrMatrix(M)
    p = size(M,2);
    C = nan(p,p);
    for a = 1:p
        for b = 1:p
            C(a,b) = localSafeCorr(M(:,a), M(:,b));
        end
    end
end

function tf = localProcessFeasible(T)
%LOCALPROCESSFEASIBLE Logical column for process feasibility (robust to type).
%   Reads a process_feasible column written as logical, 0/1 or "true"/"false".
%   Legacy datasets lacking the column are treated as feasible (unknown -> true).
    n = height(T);
    if ~ismember('process_feasible', T.Properties.VariableNames)
        tf = true(n,1); return;
    end
    x = T.process_feasible;
    if islogical(x)
        tf = x(:);
    elseif isnumeric(x)
        tf = x(:) ~= 0;
    else
        s = lower(strtrim(string(x)));
        tf = (s=="true") | (s=="1") | (s=="yes");
        tf = tf(:);
    end
end

function r = localColCorr(T, a, b)
%LOCALCOLCORR Safe correlation between two named columns; NaN if either missing.
    if ~ismember(a, T.Properties.VariableNames) || ~ismember(b, T.Properties.VariableNames)
        r = NaN; return;
    end
    r = localSafeCorr(T.(a), T.(b));
end
