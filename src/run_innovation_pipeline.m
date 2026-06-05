% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_INNOVATION_PIPELINE  Master driver for the AI-supervised innovation layer.
%
%   Orchestrates the full innovation extension on top of the classic study:
%     0. prerequisites (point surrogates, policy)        [auto-build if missing]
%     1. dataset summaries (base) + model equation summary + AI model audit
%     2. uncertainty-aware surrogates (quantile regression forests)
%     3. robust (uncertainty-aware) Pareto optimization
%     4. AI-supervised closed-loop study     [skippable: CIP_INNOVATION_SKIP_CLOSED_LOOP=1]
%     5. virtual supervisory recommendation behind the deterministic SAFETY SHIELD
%     6. counterfactual (what-if) study
%     7. AI decision dossier (+ run manifest)
%
%   The classic pipeline (run_full_pipeline.m) is left untouched. This driver
%   reuses its stable stages and adds the uncertainty / robustness / safety /
%   causal layers. Gemini proposes; deterministic MATLAB decides; the safety
%   shield gates; human approval is mandatory; nothing is real-time control.
%
%   >>> ALL DATA ARE SIMULATION-GENERATED SYNTHETIC DATA. <<<
%
%   Usage:
%     addpath('src'); run('src/run_innovation_pipeline.m')
%     setenv('CIP_INNOVATION_SKIP_CLOSED_LOOP','1');  % faster: skip the 8-min loop
%
%   See also: RUN_FULL_PIPELINE, RUN_AI_CLOSED_LOOP_STUDY, SAFETY_SHIELD.

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
try
    load_dotenv();
catch
    % .env optional; Gemini layer falls back to MOCK without a key
end
P = cip_parameters();
resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end

skipLoop = strcmp(getenv('CIP_INNOVATION_SKIP_CLOSED_LOOP'),'1');

fprintf('\n################################################################\n');
fprintf('#  AI-SUPERVISED INNOVATION PIPELINE - dairy CIP digital twin   #\n');
fprintf('#  uncertainty-aware robust optimization + deterministic shield #\n');
fprintf('#  Output is SIMULATION-GENERATED SYNTHETIC DATA (not real).    #\n');
fprintf('################################################################\n');
pipeTic = tic;
fails = {};   % accumulates labels of failed steps (critical ones flagged loudly)

% ---- Prerequisites ----------------------------------------------------------
setenv('CIP_DATASET_CSV','');   % operate on the base dataset for prerequisites
if exist(fullfile(root,'data','dairy_cip_synthetic_dataset.csv'),'file') ~= 2
    fprintf(2,['[innovation] Base dataset missing. Run run_full_pipeline (or ', ...
        'run_cip_scenarios) first.\n']);
    return;
end
if exist(fullfile(resDir,'surrogate_models.mat'),'file') ~= 2
    fails = runStep(fails, '0a. Point surrogates (prereq)', @() localRunScript(fullfile(here,'train_surrogate_models.m')), true);
end
% A clean, neutral policy for the innovation demo (balanced_default). Users can
% re-run gemini_policy_translator with another profile to change the context.
fails = runStep(fails, '0b. Policy (balanced_default)', @() gemini_policy_translator('', struct('profile','balanced_default')), true);

% ---- 1. Summaries + model audit (context for AI + shield) -------------------
fails = runStep(fails, '1a. Dataset summary (base)',   @() localRunScript(fullfile(here,'build_dataset_summary.m')), true);
fails = runStep(fails, '1b. Model equation summary',   @() build_model_equation_summary(), false);
fails = runStep(fails, '1c. AI model audit',           @() gemini_model_auditor(), false);

% ---- 2. Uncertainty-aware surrogates ---------------------------------------
fails = runStep(fails, '2. Uncertainty surrogates',    @() localRunScript(fullfile(here,'train_uncertainty_surrogates.m')), true);

% ---- 3. Robust Pareto -------------------------------------------------------
fails = runStep(fails, '3. Robust Pareto',             @() localRunScript(fullfile(here,'optimize_cip_robust_pareto.m')), true);

% ---- 4. Closed-loop AI study (optional) ------------------------------------
combCsv = fullfile(root,'data','dairy_cip_combined_dataset.csv');
if skipLoop
    fprintf('\n==== 4. Closed-loop AI study : SKIPPED (CIP_INNOVATION_SKIP_CLOSED_LOOP=1) ====\n');
else
    fails = runStep(fails, '4. Closed-loop AI study',  @() localRunScript(fullfile(here,'run_ai_closed_loop_study.m')), false);
    % The loop changes the active policy via its own runs; restore balanced_default
    % for a clean final supervisory recommendation.
    fails = runStep(fails, '4b. Restore policy',        @() gemini_policy_translator('', struct('profile','balanced_default')), true);
    % CRITICAL: the closed loop grew the dataset (base + AI-designed). Re-train the
    % uncertainty surrogates and re-build the robust front on that COMBINED dataset
    % so the recommender's preferred (robust) front reflects the latest feedback,
    % not the base-only models from steps 2-3.
    if exist(combCsv,'file')==2
        setenv('CIP_DATASET_CSV', combCsv);
        fails = runStep(fails, '4b2. Uncertainty surrogates (combined)', @() localRunScript(fullfile(here,'train_uncertainty_surrogates.m')), true);
        setenv('CIP_DATASET_CSV','');
        fails = runStep(fails, '4b3. Robust Pareto (combined)', @() localRunScript(fullfile(here,'optimize_cip_robust_pareto.m')), true);
    end
end

% ---- 4c. Pareto front for the active policy (full generations) -------------
% Always regenerate the point front against the current surrogates and the
% active (balanced_default) policy, at full GA generations, so the supervisory
% step selects from a high-quality, policy-consistent front (the closed loop, if
% it ran, leaves a reduced-generation front).
setenv('CIP_GA_POP',''); setenv('CIP_GA_MAXGEN','');   % full-quality optimization
fails = runStep(fails, '4c. Pareto front (active policy)', @() localRunScript(fullfile(here,'optimize_cip_pareto.m')), true);

% ---- 5. Supervisory recommendation behind the safety shield ----------------
fails = runStep(fails, '5. Supervisory recommendation (+ safety shield)', ...
    @() ai_supervisory_control_recommender(struct('timestamp', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')))), true);

% ---- 6. Counterfactual study -----------------------------------------------
fails = runStep(fails, '6. Counterfactual study',      @() localRunScript(fullfile(here,'run_counterfactual_cip_study.m')), true);

% ---- 6b. Restore the canonical (base) dataset summary ----------------------
% The closed loop leaves dataset_summary.json describing the COMBINED set; make
% the canonical summary describe the BASE dataset again (the manifest counts the
% base dataset rows), so the row-count consistency check is clean. The combined
% summary remains in results/dataset_summary_combined.json.
setenv('CIP_DATASET_CSV','');
fails = runStep(fails, '6b. Restore base dataset summary', @() localRunScript(fullfile(here,'build_dataset_summary.m')), false);

% ---- 7. Run manifest + decision dossier ------------------------------------
% Manifest first so the dossier picks up the current run id / row counts.
fails = runStep(fails, '7a. Run manifest',             @() build_run_manifest(), false);
fails = runStep(fails, '7b. AI decision dossier',      @() build_ai_decision_dossier(), true);

% ---- Summary ----------------------------------------------------------------
fprintf('\n==== Innovation artifacts ====\n');
localList(fullfile(root,'models','uncertainty_surrogates.mat'));
localList(fullfile(resDir,'uncertainty_surrogate_metrics.csv'));
localList(fullfile(resDir,'robust_pareto_solutions.csv'));
localList(fullfile(resDir,'ai_supervisory_recommendation.json'));
localList(fullfile(resDir,'counterfactual_cip_results.csv'));
localList(fullfile(resDir,'counterfactual_cip_report.md'));
localList(fullfile(resDir,'ai_decision_dossier.md'));
localList(fullfile(resDir,'run_manifest.json'));
if ~skipLoop; localList(fullfile(resDir,'ai_closed_loop_trace.json')); end

% ---- Status (do NOT report COMPLETE if steps failed) ------------------------
elapsed = toc(pipeTic);
if isempty(fails)
    fprintf('\n[innovation] COMPLETE in %.1f s. Results are SYNTHETIC, proof-of-concept; human approval required.\n', elapsed);
else
    nCrit = sum(contains(fails, '[CRITICAL]'));
    fprintf(2,'\n[innovation] INCOMPLETE in %.1f s: %d step(s) failed (%d critical). Artifacts may be stale/mixed:\n', ...
        elapsed, numel(fails), nCrit);
    for i = 1:numel(fails); fprintf(2,'   - %s\n', fails{i}); end
    fprintf(2,'   Re-run after fixing the above before trusting the dossier/recommendation.\n');
end

%% ===== Local functions ======================================================
function fails = runStep(fails, label, fcn, critical)
%RUNSTEP Run one step; on failure, record it (and flag critical failures so the
%   pipeline does not silently report COMPLETE on a broken/incomplete run).
    if nargin < 4; critical = false; end
    fprintf('\n==== %s ====\n', label);
    t = tic;
    try
        fcn();
        fprintf('---- %s : OK (%.1f s)\n', label, toc(t));
    catch ME
        tag = '';
        if critical; tag = ' [CRITICAL]'; end
        fprintf(2,'**** %s : FAILED%s -> %s\n', label, tag, ME.message);
        fails{end+1} = sprintf('%s%s', label, tag);
    end
end

function localList(p)
    if exist(p,'file'); tag = 'OK '; else; tag = '?? '; end
    fprintf('  [%s] %s\n', tag, p);
end

function localRunScript(scriptPath)
%LOCALRUNSCRIPT Run a script in this helper's own (non-static) workspace, so
%   script-leftover variables never shadow names in the driver's workspace.
    run(scriptPath);
end
