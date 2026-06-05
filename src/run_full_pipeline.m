% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_FULL_PIPELINE  End-to-end driver for the dairy CIP digital-twin study.
%
%   Runs the full four-layer workflow:
%     (1) Simulink mechanistic simulation -> synthetic dataset  [CRITICAL]
%     (2) Dataset validation                                    [non-critical]
%     (3) ML surrogate training                                 [CRITICAL]
%     (4) Gemini policy translation                             [non-critical]
%     (5) Pareto multi-objective optimization                   [CRITICAL]
%     (6) Manuscript/audit metadata and summaries                [non-critical]
%     (7) Gemini audit/explanation                              [non-critical]
%     (8) Python manuscript CSV dependencies                     [non-critical]
%     (9) Python figures and Word tables                         [non-critical]
%
%   PIPELINE STATUS:
%     OK      - all steps (including all 3 critical) succeeded.
%     PARTIAL - all 3 critical steps succeeded; >= 1 non-critical step failed.
%     FAILED  - at least one CRITICAL step failed.
%   The word "COMPLETE" only appears when status == OK.
%   A machine-readable sentinel is written to results/_pipeline_status.txt.
%
%   CONFIGURATION PRECEDENCE (lowest -> highest):
%     1. Built-in defaults (N_SCENARIOS = 5000, etc.)
%     2. .env file (fills UNSET env vars only; does NOT overwrite session values)
%     3. Explicit session setenv() calls (always win)
%
%   >>> ALL GENERATED DATA ARE SIMULATION-GENERATED SYNTHETIC DATA. <<<
%
%   Usage:
%     Smoke test (50 scenarios, mock Gemini, overrides .env):
%       setenv('CIP_N_SCENARIOS','50'); setenv('CIP_GEMINI_MODE','mock');
%       run('src/run_full_pipeline.m')
%     Live Gemini (set BEFORE running):
%       setenv('GEMINI_API_KEY','...'); run('src/run_full_pipeline.m')
%
%   See also: RUN_CIP_SCENARIOS, TRAIN_SURROGATE_MODELS, OPTIMIZE_CIP_PARETO.

%% ----- Setup ----------------------------------------------------------------
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();

% --- Configuration precedence (default < .env < explicit) --------------------
% Step 1: capture any keys ALREADY set by the caller (highest precedence).
%   e.g. setenv('CIP_N_SCENARIOS','50') before run() must not be overridden.
% Step 2: load .env but ONLY for UNSET keys (load_dotenv default behaviour).
try
    envStatus = load_dotenv();   % fills unset keys only; does NOT clobber session
    if ~isempty(envStatus.skipped)
        fprintf('[pipeline] .env loaded (%d key(s) skipped — already set by caller).\n', ...
            numel(envStatus.skipped));
    end
catch
    envStatus = struct('hasGeminiKey',false);
end

% Step 3: resolve N_SCENARIOS. Explicit session value wins; .env may have set
% CIP_N_SCENARIOS for an unset key; fallback to built-in default 5000.
N_SCENARIOS = 5000;     % built-in default (full study; >= 5000)
preN = getenv('CIP_N_SCENARIOS');
if isempty(preN)
    setenv('CIP_N_SCENARIOS', num2str(N_SCENARIOS));  % consumed by run_cip_scenarios
else
    N_SCENARIOS = str2double(preN);
    if ~isfinite(N_SCENARIOS) || N_SCENARIOS < 1
        N_SCENARIOS = 5000;
        setenv('CIP_N_SCENARIOS', '5000');
    end
    fprintf('[pipeline] Using CIP_N_SCENARIOS=%s (caller/session/env; built-in default=5000).\n', preN);
end

% Gemini mode: auto|mock|live. Set CIP_GEMINI_MODE=mock for offline smoke tests.
geminiMode = getenv('CIP_GEMINI_MODE');
if isempty(geminiMode); geminiMode = 'auto'; end

fprintf('\n');
fprintf('################################################################\n');
fprintf('#  SELF-EXPLAINING DIGITAL TWIN - DAIRY CIP (proof of concept)  #\n');
fprintf('#  Output is SIMULATION-GENERATED SYNTHETIC DATA (not real).    #\n');
fprintf('################################################################\n');
fprintf('[pipeline] N_SCENARIOS=%d  GEMINI_MODE=%s\n', N_SCENARIOS, geminiMode);
pipeTic = tic;

%% ----- Toolbox inventory ----------------------------------------------------
fprintf('\n==== Toolbox availability ====\n');
tb = { 'Simulink','Simulink'; ...
       'Stateflow','Stateflow'; ...
       'Statistics & ML','Statistics_Toolbox'; ...
       'Global Optimization','GADS_Toolbox'; ...
       'Parallel Computing','Distrib_Computing_Toolbox'; ...
       'Deep Learning','Neural_Network_Toolbox' };
for i = 1:size(tb,1)
    fprintf('  %-22s : %s\n', tb{i,1}, ternary(license('test',tb{i,2}),'available','MISSING'));
end

%% ----- Model presence -------------------------------------------------------
mdlFile = fullfile(root,'model',[P.model_name '.slx']);
if exist(mdlFile,'file')==4 || exist(mdlFile,'file')==2
    try
        load_system(mdlFile);
        fprintf('\n[pipeline] Loaded model: %s\n', mdlFile);
    catch ME
        fprintf(2,'\n[pipeline] Could not load model (%s).\n', ME.message);
    end
else
    fprintf(2,['\n[pipeline] WARNING: Simulink model not found:\n  %s\n' ...
        '  Build model/%s.slx first (build_model.m).\n'], mdlFile, P.model_name);
end

%% ----- Pipeline steps -------------------------------------------------------
% Each script step is executed via localRunScript so that run() operates in a
% fresh, NON-static function workspace. (This script file defines local
% functions, which makes its own workspace static; running a script directly in
% a static workspace would error with "Attempt to add 'here' to a static
% workspace".) Inter-step data is exchanged through files on disk, not the
% workspace, so isolation is the correct design here.
%
% CRITICAL steps: (1) scenarios, (3) surrogates, (5) Pareto. A CRITICAL failure
% causes FAILED status; all others cause PARTIAL at worst.
steps = { ...
    '1. Scenario generation (Simulink)', @() localRunScript(fullfile(here,'run_cip_scenarios.m')),        true; ...
    '2. Dataset validation',             @() localRunScript(fullfile(here,'validate_outputs.m')),          false; ...
    '3. Surrogate training (ML)',        @() localRunScript(fullfile(here,'train_surrogate_models.m')),    true; ...
    '4. Gemini policy translation',      @() gemini_policy_translator(),                                    false; ...
    '5. Pareto optimization',            @() localRunScript(fullfile(here,'optimize_cip_pareto.m')),       true; ...
    '6. Model metadata for manuscript tables', @() build_model_equation_summary(),                         false; ...
    '7. Dataset summary (for audit)',    @() localRunScript(fullfile(here,'build_dataset_summary.m')),     false; ...
    '8. Gemini plausibility audit',      @() gemini_plausibility_auditor(),                                false; ...
    '9. Gemini Pareto explanation',      @() gemini_explain_pareto(),                                      false; ...
    '10. Demo time-series CSVs for Python figures', @() localRunScript(fullfile(here,'run_demo_simulations.m')), false; ...
    '11. Counterfactual CSV for Python figures', @() localRunScript(fullfile(here,'run_counterfactual_cip_study.m')), false; ...
    '12. Policy portfolio CSV for Python figures', @() localRunScript(fullfile(here,'run_policy_portfolio.m')), false; ...
    '12b. Figure-derived data export (MATLAB)', @() export_figure_data(),                                  false ...
    % Steps 13 and 14 (Python figures and tables) are excluded from the automatic pipeline.
    % They are generated manually from the Python scripts under the manuscript/ folder.
    % '13. Figures (Python manuscript)',   @() localRunScript(fullfile(here,'plot_results.m')),              false; ...
    % '14. Tables (Python DOCX)',          @() localRunPythonScript(fullfile(root,'manuscript','make_tables.py')), false ...
};
nSteps  = size(steps,1);
stepOk  = false(nSteps,1);
stepSec = nan(nSteps,1);
stepErr = strings(nSteps,1);

for si = 1:nSteps
    label  = steps{si,1};
    fcn    = steps{si,2};
    isCrit = steps{si,3};
    [ok, secs, errMsg] = runStep(label, fcn);
    stepOk(si)  = ok;
    stepSec(si) = secs;
    stepErr(si) = errMsg;
    if ~ok && isCrit
        fprintf(2,'**** CRITICAL STEP FAILED: %s -> pipeline will be FAILED.\n', label);
    end
end

%% ----- Gemini mode + final summary ------------------------------------------
hasKey = ~isempty(getenv('GEMINI_API_KEY'));
fprintf('\n==== Generative-AI layer ====\n');
fprintf('  Mode: %s\n', upper(geminiMode));
if strcmp(geminiMode,'mock')
    fprintf('  CIP_GEMINI_MODE=mock: all Gemini calls ran in forced MOCK[forced] mode.\n');
elseif hasKey
    fprintf('  GEMINI_API_KEY detected: Gemini calls attempted LIVE (with mock fallback on error).\n');
else
    fprintf('  GEMINI_API_KEY not set: Gemini layer ran in MOCK[fallback] mode.\n');
end

%% ----- Per-step status table -----------------------------------------------
fprintf('\n==== Step results ====\n');
for si = 1:nSteps
    isCrit = steps{si,3};
    tag = ternary(stepOk(si), '[OK  ]', ternary(isCrit, '[FAIL]', '[WARN]'));
    critMark = ternary(isCrit, ' *CRITICAL', '');
    fprintf('  %s %s%s (%.1f s)\n', tag, steps{si,1}, critMark, stepSec(si));
    if ~stepOk(si) && strlength(stepErr(si)) > 0
        fprintf('         -> %s\n', stepErr(si));
    end
end

%% ----- Overall pipeline status ----------------------------------------------
critMask = logical(cell2mat(steps(:,3)));
allCritOk = all(stepOk(critMask));
allOk     = all(stepOk);

if allOk
    pipeStatus = 'OK';
    statusMsg  = 'PIPELINE COMPLETE';
elseif allCritOk
    pipeStatus = 'PARTIAL';
    statusMsg  = 'PIPELINE PARTIAL (all critical steps OK; non-critical failures above)';
else
    pipeStatus = 'FAILED';
    statusMsg  = 'PIPELINE FAILED (critical step(s) failed -- see errors above)';
end

%% ----- Machine-readable run manifest ---------------------------------------
try
    build_run_manifest(struct( ...
        'pipeline_status', pipeStatus, ...
        'pipeline_steps', localStepManifest(steps, stepOk, stepSec, stepErr)));
catch ME
    fprintf(2,'[pipeline] WARNING: could not update results/run_manifest.json (%s).\n', ME.message);
end

%% ----- Artifact list -------------------------------------------------------
resDir = fullfile(root,'results'); figDir = fullfile(root,'figures');
fprintf('\n==== Artifacts ====\n');
localList(fullfile(root,'data','dairy_cip_synthetic_dataset.csv'));
localList(fullfile(resDir,'dataset_validation_report.txt'));
localList(fullfile(resDir,'surrogate_models.mat'));
localList(fullfile(resDir,'surrogate_metrics.csv'));
localList(fullfile(resDir,'surrogate_pred_vs_obs.csv'));
localList(fullfile(resDir,'selected_policy_config.json'));
localList(fullfile(resDir,'pareto_solutions.csv'));
localList(fullfile(resDir,'model_equation_summary.json'));
localList(fullfile(resDir,'dataset_summary.json'));
localList(fullfile(resDir,'plausibility_audit.json'));
localList(fullfile(resDir,'gemini_decision_report.txt'));
localList(fullfile(resDir,'demo_timeseries_baseline.csv'));
localList(fullfile(resDir,'counterfactual_cip_results.csv'));
localList(fullfile(resDir,'policy_portfolio_results.csv'));
localList(fullfile(resDir,'run_manifest.json'));
tabDir = fullfile(root,'tables');
localList(fullfile(figDir,'Fig1_process_dynamics.png'));
localList(fullfile(figDir,'Fig2_kpi_distributions.png'));
localList(fullfile(figDir,'Fig3_correlation_heatmap.png'));
localList(fullfile(figDir,'Fig4_sensitivities.png'));
localList(fullfile(figDir,'Fig5_surrogate_parity.png'));
localList(fullfile(figDir,'Fig6_pareto_fronts.png'));
localList(fullfile(figDir,'Fig7_counterfactual_effects.png'));
localList(fullfile(figDir,'Fig8_policy_portfolio.png'));
localList(fullfile(figDir,'FigS1_recipe_trajectories.png'));
localList(fullfile(tabDir,'Table1_model_parameters.docx'));
localList(fullfile(tabDir,'Table2_variables_bounds.docx'));
localList(fullfile(tabDir,'Table3_descriptive_statistics.docx'));
localList(fullfile(tabDir,'Table4_surrogate_metrics.docx'));
localList(fullfile(tabDir,'Table5_pareto_recipes.docx'));
localList(fullfile(tabDir,'Table6_policy_portfolio.docx'));


%% ----- Banner + machine-readable sentinel ----------------------------------
fprintf('\n==== RESULT ====\n');
fprintf('[pipeline] %s in %.1f s.\n', statusMsg, toc(pipeTic));
fprintf('[pipeline] Remember: results are SYNTHETIC, proof-of-concept only.\n');

% Write machine-readable sentinel (gitignored by results/_*.txt pattern).
sentPath = fullfile(resDir,'_pipeline_status.txt');
if ~exist(resDir,'dir'); mkdir(resDir); end
try
    fid = fopen(sentPath,'w');
    if fid > 0
        fprintf(fid,'PIPELINE_STATUS=%s\n', pipeStatus);
        fprintf(fid,'N_SCENARIOS=%d\n', N_SCENARIOS);
        fprintf(fid,'GEMINI_MODE=%s\n', geminiMode);
        fprintf(fid,'ELAPSED_S=%.1f\n', toc(pipeTic));
        fprintf(fid,'STEPS:\n');
        for si = 1:nSteps
            isCrit = steps{si,3};
            fprintf(fid,'  [%s] %s%s\n', ternary(stepOk(si),'OK','FAIL'), ...
                steps{si,1}, ternary(isCrit,' [CRITICAL]',''));
        end
        fclose(fid);
    end
catch
end

%% ===== Local functions ======================================================
function [ok, secs, errMsg] = runStep(label, fcn)
    fprintf('\n==== %s ====\n', label);
    t = tic;
    ok = false; errMsg = '';
    try
        fcn();
        ok = true;
        fprintf('---- %s : OK (%.1f s)\n', label, toc(t));
    catch ME
        errMsg = ME.message;
        fprintf(2,'**** %s : FAILED -> %s\n', label, ME.message);
    end
    secs = toc(t);
end

function localList(p)
    if exist(p,'file'); tag = 'OK '; else; tag = '?? '; end
    fprintf('  [%s] %s\n', tag, p);
end

function out = ternary(c,a,b)
    if c; out = a; else; out = b; end
end

function localRunScript(scriptPath)
%LOCALRUNSCRIPT Run a script in this helper's own (non-static) workspace.
%   Steps exchange data via files on disk, so no variables need to cross back.
    run(scriptPath);
end

function localRunPythonScript(scriptPath)
%LOCALRUNPYTHONSCRIPT Run a repository Python script by absolute path.
    if exist(scriptPath,'file') ~= 2
        error('run_full_pipeline:noPythonScript','Python script not found:\n  %s', scriptPath);
    end
    pythonCmd = strtrim(getenv('CIP_PYTHON_CMD'));
    if isempty(pythonCmd); pythonCmd = 'python'; end
    [status, cmdOut] = system(sprintf('%s "%s"', pythonCmd, scriptPath));
    if ~isempty(strtrim(cmdOut)); fprintf('%s\n', cmdOut); end
    if status ~= 0
        error('run_full_pipeline:pythonFailed', ...
            'Python script failed with status %d:\n  %s', status, scriptPath);
    end
end

function s = localStepManifest(steps, stepOk, stepSec, stepErr)
%LOCALSTEPMANIFEST Compact per-step status for results/run_manifest.json.
    n = size(steps,1);
    s = repmat(struct('name','','status','','critical',false,'elapsed_s',NaN,'error',''), n, 1);
    for ii = 1:n
        isCrit = steps{ii,3};
        s(ii).name = steps{ii,1};
        s(ii).status = ternary(stepOk(ii), 'OK', ternary(isCrit, 'FAILED', 'PARTIAL'));
        s(ii).critical = isCrit;
        s(ii).elapsed_s = stepSec(ii);
        s(ii).error = char(stepErr(ii));
    end
end
