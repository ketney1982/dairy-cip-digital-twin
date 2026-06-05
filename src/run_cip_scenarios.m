% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_CIP_SCENARIOS  Generate the synthetic dairy-CIP dataset by simulation.
%
%   This script performs Monte-Carlo simulation of the Simulink digital twin
%   (dairy_cip_digital_twin) over randomized CIP scenarios and assembles the
%   results into a single CSV dataset.
%
%   >>> THE OUTPUT IS SIMULATION-GENERATED SYNTHETIC DATA. <<<
%   It is NOT real industrial data and must never be presented as such.
%
%   Reproducibility:
%     * rng(42) fixes the scenario sampling.
%     * Scenarios are configured with Simulink.SimulationInput (NO assignin).
%     * parsim + Fast Restart are used when the Parallel Computing Toolbox is
%       available; otherwise the script falls back to a serial sim loop.
%
%   Configuration:
%     * The number of scenarios N is read from the environment variable
%       CIP_N_SCENARIOS when set (used by run_full_pipeline for quick tests);
%       otherwise N defaults to 5000.
%     * Parallel Computing Toolbox is used through parsim when available.
%       Set CIP_PARALLEL_WORKERS to choose the local CPU worker count, or
%       CIP_FORCE_SERIAL=true to force the serial Fast Restart loop.
%
%   Output:
%     data/dairy_cip_synthetic_dataset.csv with EXPLICIT, separated status columns
%     so numerical success is never conflated with process feasibility or hygiene:
%       * solver_status     - pure numerical sim outcome (success | failed).
%       * process_feasible  - solver succeeded AND outputs finite & in physical range.
%       * quality_status    - hygiene/quality class (pass | below_hygiene_floor |
%                             infeasible); NOT the same as solver success.
%       * simulation_status - retained backward-compatible ALIAS of solver_status.
%     Plus COD_chem_equiv_mgL (= COD_chemical_factor * NaOH_residual_mgL), the
%     chemical COD-equivalent reported SEPARATELY from the organic COD_mgL proxy.
%
%   See also: CIP_PARAMETERS, VALIDATE_OUTPUTS, RUN_FULL_PIPELINE.

%% ----- Paths and parameters -------------------------------------------------
here = fileparts(mfilename('fullpath'));   % .../src
root = fileparts(here);                     % project root
addpath(here);
P = cip_parameters();

dataDir = fullfile(root,'data');
if ~exist(dataDir,'dir'); mkdir(dataDir); end
csvPath = fullfile(dataDir,'dairy_cip_synthetic_dataset.csv');

%% ----- Number of scenarios --------------------------------------------------
N = 5000;                       % default; >= 5000 as required
% N = 50;                       % <-- uncomment for a quick local test run
envN = getenv('CIP_N_SCENARIOS');
if ~isempty(envN)
    nTmp = str2double(envN);
    if isfinite(nTmp) && nTmp >= 1
        N = round(nTmp);
    else
        warning('run_cip_scenarios:badEnvN', ...
            'CIP_N_SCENARIOS=%s is invalid; using N=%d.', envN, N);
    end
end
fprintf('[run_cip_scenarios] Generating %d synthetic CIP scenarios.\n', N);

%% ----- Load the Simulink model ----------------------------------------------
mdl     = P.model_name;
mdlFile = fullfile(root,'model',[mdl '.slx']);
if exist(mdlFile,'file') ~= 4 && exist(mdlFile,'file') ~= 2
    error('run_cip_scenarios:noModel', ...
        ['Simulink model not found:\n  %s\n' ...
         'Build the model first (model/%s.slx) before running scenarios.'], ...
        mdlFile, mdl);
end
load_system(mdlFile);

%% ----- Sample scenarios (uniform within bounds) -----------------------------
rng(42);
lb = P.lb; ub = P.ub;                 % 1x10, aligned with P.var_names
U  = rand(N, numel(lb));
X  = lb + U .* (ub - lb);             % N x 10 sampled scenario matrix

% Column indices into X (P.var_names order).
iT=1; iQ=2; ipre=3; ialk=4; iint=5; ifin=6; iNaOH=7; isoil=8; ihr=9; iwr=10;

stopTime = X(:,ipre) + X(:,ialk) + X(:,iint) + X(:,ifin);   % N x 1, seconds
T_in_C   = P.T_in_C;                                          % fixed inlet temp

%% ----- Build SimulationInput array ------------------------------------------
clear simIn
simIn(1:N) = Simulink.SimulationInput(mdl);
% Scenario variables are injected into the MODEL workspace via the 'Workspace'
% option so they override the build-time model-workspace defaults (a base-target
% setVariable would be shadowed by them). No assignin to the base workspace.
for i = 1:N
    s = Simulink.SimulationInput(mdl);
    s = s.setVariable('T_C',       X(i,iT),    'Workspace', mdl);
    s = s.setVariable('Q_m3h',     X(i,iQ),    'Workspace', mdl);
    s = s.setVariable('t_pre',     X(i,ipre),  'Workspace', mdl);
    s = s.setVariable('t_alk',     X(i,ialk),  'Workspace', mdl);
    s = s.setVariable('t_int',     X(i,iint),  'Workspace', mdl);
    s = s.setVariable('t_final',   X(i,ifin),  'Workspace', mdl);
    s = s.setVariable('NaOH_pct',  X(i,iNaOH), 'Workspace', mdl);
    s = s.setVariable('soil0',     X(i,isoil), 'Workspace', mdl);
    s = s.setVariable('heat_rec',  X(i,ihr),   'Workspace', mdl);
    s = s.setVariable('water_rec', X(i,iwr),   'Workspace', mdl);
    s = s.setVariable('T_in_C',    T_in_C,     'Workspace', mdl);
    s = s.setModelParameter('StopTime', num2str(stopTime(i)));
    s = s.setModelParameter('SignalLogging','on');
    s = s.setModelParameter('SignalLoggingName','logsout');
    simIn(i) = s;
end

%% ----- Run simulations (parsim + Fast Restart, serial fallback) -------------
% Detect parsim robustly: it ships as a packaged .p file (exist(...)==6), so
% test discoverability via which() rather than a specific exist() code.
hasPCT = license('test','Distrib_Computing_Toolbox') && ~isempty(which('parsim')) ...
    && ~localEnvBool('CIP_FORCE_SERIAL', false);
simOut = [];
ranParallel = false;
if hasPCT
    try
        localPrepareParallelPool(N);
        % Base-workspace transfer is intentionally NOT configured: every scenario
        % input is injected into the MODEL workspace via SimulationInput.setVariable,
        % so there is nothing to transfer from the base workspace (project
        % convention: no base-workspace state). Omitting the option also clears the
        % XFRWSP advisory that flags 'TransferBaseWorkspaceVariables' for parsim.
        simOut = parsim(simIn, ...
            'ShowProgress','on', ...
            'UseFastRestart','on', ...
            'StopOnError','off');
        ranParallel = true;
    catch ME
        warning('run_cip_scenarios:parsimFailed', ...
            'parsim failed (%s); falling back to serial sim.', ME.message);
        simOut = [];
    end
end

if isempty(simOut)
    % Serial fallback with Fast Restart where possible.
    fastOK = false;
    try
        set_param(mdl,'FastRestart','on');
        fastOK = true;
    catch
        % FastRestart unavailable for this model config; proceed without it.
    end
    cleanupObj = onCleanup(@() localTurnOffFastRestart(mdl, fastOK));
    tmp = cell(N,1);
    for i = 1:N
        try
            tmp{i} = sim(simIn(i));
        catch ME
            tmp{i} = ME;                               % store error object for later
        end
        if mod(i,max(1,round(N/20)))==0
            fprintf('[run_cip_scenarios] serial sim %d/%d\n', i, N);
        end
    end
    simOut = tmp;   % cell array (SimulationOutput or MException per element)
end

%% ----- Extract outputs ------------------------------------------------------
scenario_id        = (1:N).';
water_L            = nan(N,1);
thermal_energy_kWh = nan(N,1);
pump_energy_kWh    = nan(N,1);
total_energy_kWh   = nan(N,1);
COD_mgL            = nan(N,1);
NaOH_residual_mgL  = nan(N,1);
CO2eq_kg           = nan(N,1);
cleaning_score     = nan(N,1);
hygienic_risk      = nan(N,1);
EHPI               = nan(N,1);
solver_status      = strings(N,1);   % pure numerical sim outcome (success/failed)

for i = 1:N
    [lo, errMsg] = localGetLogsout(simOut, i, ranParallel);
    if ~isempty(errMsg) || isempty(lo)
        solver_status(i) = "failed";
        continue;
    end
    try
        water_L(i)            = getFinal(lo,'water_L');
        thermal_energy_kWh(i) = getFinal(lo,'thermal_energy_kWh');
        pump_energy_kWh(i)    = getFinal(lo,'pump_energy_kWh');
        COD_mgL(i)            = getFinal(lo,'COD_mgL');
        NaOH_residual_mgL(i)  = getFinal(lo,'NaOH_residual_mgL');
        CO2eq_kg(i)           = getFinal(lo,'CO2eq_kg');
        cleaning_score(i)     = getFinal(lo,'cleaning_score');
        hygienic_risk(i)      = getFinal(lo,'hygienic_risk');
        EHPI(i)               = getFinal(lo,'EHPI');
        total_energy_kWh(i)   = thermal_energy_kWh(i) + pump_energy_kWh(i);
        solver_status(i)  = "success";
    catch
        solver_status(i)  = "failed";
    end
end

%% ----- Derived reporting columns: organic vs chemical COD; status split -----
% Chemical COD-equivalent of NaOH residual, reported SEPARATELY from organic
% COD_mgL so the two are never conflated (NaN-safe: NaN inputs stay NaN).
COD_chem_equiv_mgL = P.COD_chemical_factor .* NaOH_residual_mgL;

% PROCESS feasibility is DISTINCT from solver success: a simulation can converge
% numerically yet yield non-physical or out-of-range outputs. A row is feasible
% only if the solver succeeded AND all key outputs are finite and in range.
finiteOk = isfinite(water_L) & isfinite(total_energy_kWh) & isfinite(COD_mgL) & ...
           isfinite(CO2eq_kg) & isfinite(cleaning_score) & isfinite(hygienic_risk) & ...
           isfinite(EHPI);
rangeOk  = (water_L>=0) & (total_energy_kWh>=0) & (COD_mgL>=0) & (CO2eq_kg>=0) & ...
           (cleaning_score>=0) & (cleaning_score<=100) & (hygienic_risk>=0) & (hygienic_risk<=1);
process_feasible = (solver_status=="success") & finiteOk & rangeOk;

% QUALITY (hygiene) class is separate again: among feasible rows, does the
% process clear the hygiene floor and the hygienic-risk cap? This keeps the
% cleaning score / hygienic risk from being read as "the simulation succeeded".
quality_status = strings(N,1);
quality_status(~process_feasible) = "infeasible";
qPass = process_feasible & (cleaning_score>=P.min_cleaning_score) & ...
        (hygienic_risk<=P.max_hygienic_risk);
quality_status(qPass) = "pass";
quality_status(process_feasible & ~qPass) = "below_hygiene_floor";

% Backward-compatible alias: legacy consumers filter simulation_status=="success".
% It mirrors solver_status exactly (the old column meant "the solver succeeded").
simulation_status = solver_status;

%% ----- Assemble and save table (exact column order) -------------------------
Tbl = table( ...
    scenario_id, ...
    X(:,iT), X(:,iQ), X(:,ipre), X(:,ialk), X(:,iint), X(:,ifin), ...
    X(:,iNaOH), X(:,isoil), X(:,ihr), X(:,iwr), repmat(T_in_C,N,1), stopTime, ...
    water_L, thermal_energy_kWh, pump_energy_kWh, total_energy_kWh, ...
    COD_mgL, NaOH_residual_mgL, COD_chem_equiv_mgL, CO2eq_kg, cleaning_score, ...
    hygienic_risk, EHPI, ...
    cellstr(solver_status), cellstr(string(process_feasible)), cellstr(quality_status), ...
    cellstr(simulation_status), ...
    'VariableNames', { ...
        'scenario_id','T_C','Q_m3h','t_pre','t_alk','t_int','t_final', ...
        'NaOH_pct','soil0','heat_rec','water_rec','T_in_C','stopTime', ...
        'water_L','thermal_energy_kWh','pump_energy_kWh','total_energy_kWh', ...
        'COD_mgL','NaOH_residual_mgL','COD_chem_equiv_mgL','CO2eq_kg','cleaning_score', ...
        'hygienic_risk','EHPI', ...
        'solver_status','process_feasible','quality_status','simulation_status'});

writetable(Tbl, csvPath);

nSolverOk = sum(solver_status=="success");
nFeasible = sum(process_feasible);
nPass     = sum(quality_status=="pass");
fprintf(['[run_cip_scenarios] Done. solver_success=%d/%d, process_feasible=%d, ' ...
         'quality_pass=%d.\n'], nSolverOk, N, nFeasible, nPass);
fprintf('[run_cip_scenarios] Saved SYNTHETIC dataset -> %s\n', csvPath);

%% ===== Local functions ======================================================
function v = getFinal(lo, name)
%GETFINAL Return the final (cycle-end) sample of a named logsout signal.
    el = lo.getElement(name);
    d  = el.Values.Data;
    v  = double(d(end));
end

function [lo, errMsg] = localGetLogsout(simOut, i, ranParallel)
%LOCALGETLOGSOUT Robustly retrieve the logsout object and any error message.
    lo = [];
    errMsg = '';
    try
        if ranParallel
            so = simOut(i);
            if ~isempty(so.ErrorMessage); errMsg = so.ErrorMessage; return; end
            lo = so.logsout;
        else
            item = simOut{i};
            if isa(item,'MException'); errMsg = item.message; return; end
            so = item;
            if isprop(so,'ErrorMessage') && ~isempty(so.ErrorMessage)
                errMsg = so.ErrorMessage; return;
            end
            lo = so.logsout;
        end
    catch ME
        errMsg = ME.message;
    end
    if isempty(lo); errMsg = sprintf('%s (no logsout)', errMsg); end
end

function localTurnOffFastRestart(mdl, fastOK)
    if fastOK
        try
            set_param(mdl,'FastRestart','off');
        catch
        end
    end
end

function localPrepareParallelPool(N)
%LOCALPREPAREPARALLELPOOL Start a local process pool when it improves parsim.
    workers = localRequestedWorkers(N);
    pool = gcp('nocreate');
    if isempty(pool) && workers > 1
        fprintf('[run_cip_scenarios] Starting local parallel pool with %d workers (set CIP_PARALLEL_WORKERS to override).\n', workers);
        parpool('local', workers);
        pool = gcp('nocreate');
    end
    if isempty(pool)
        fprintf('[run_cip_scenarios] No parallel pool started; parsim may auto-start one or fall back internally.\n');
    else
        fprintf('[run_cip_scenarios] parsim using pool: %d workers.\n', pool.NumWorkers);
    end
end

function workers = localRequestedWorkers(N)
%LOCALREQUESTEDWORKERS Choose a conservative CPU worker count for this host.
    envWorkers = localEnvNum('CIP_PARALLEL_WORKERS', NaN);
    if isfinite(envWorkers)
        workers = max(1, min(N, envWorkers));
        return;
    end
    try
        maxLocal = parcluster('local').NumWorkers;
    catch
        maxLocal = inf;
    end
    try
        nCores = feature('numcores');
    catch
        nCores = 2;
    end
    workers = max(1, min([N, maxLocal, max(1, nCores - 1)]));
end

function v = localEnvNum(name, default)
%LOCALENVNUM Return a positive finite integer from an env var, else the default.
    v = default;
    s = getenv(name);
    if ~isempty(s)
        x = str2double(s);
        if isfinite(x) && x >= 1
            v = round(x);
        end
    end
end

function v = localEnvBool(name, default)
%LOCALENVBOOL Return a logical from an env var ('true'/'1' -> true, 'false'/'0' -> false).
    v = default;
    s = lower(strtrim(getenv(name)));
    if strcmp(s,'true') || strcmp(s,'1')
        v = true;
    elseif strcmp(s,'false') || strcmp(s,'0')
        v = false;
    end
end
