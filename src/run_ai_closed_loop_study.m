% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_AI_CLOSED_LOOP_STUDY  AI-supervised closed-loop digital-twin study.
%
%   Runs an agentic loop ENTIRELY INSIDE THE DIGITAL TWIN (never the plant):
%   the generative-AI layer proposes hypotheses and experiments, the Simulink
%   twin simulates them, deterministic MATLAB validates the hypotheses and
%   audits the model, surrogates are retrained on the GROWING (base + AI-designed)
%   dataset, the Pareto front is recomputed, and a virtual supervisory
%   recommendation is produced behind a deterministic safety gate.
%
%   Per iteration (default N=3, override with CIP_CLOSED_LOOP_ITERS):
%     1. build_dataset_summary        (context)
%     2. gemini_hypothesis_generator  (AI proposes)
%     3. gemini_experiment_designer   (AI proposes; MATLAB clamps)
%     4. run_ai_designed_scenarios    (Simulink simulates)
%     5. validate_ai_hypotheses       (deterministic; no Gemini)
%     6. gemini_model_auditor         (AI flags; no parameter change)
%     7. train_surrogate_models       (retrain on base + accumulated AI-designed)
%     8. optimize_cip_pareto          (numeric optimization)
%     9. ai_supervisory_control_recommender (virtual, gated, human-approvable)
%
%   GOVERNANCE: Gemini is never inside the Simulink solver or gamultiobj and is
%   never ground truth. Every numeric decision is deterministic MATLAB; the
%   safety gate can reject or mark recommendations research-only; human approval
%   is mandatory. ALL DATA ARE SIMULATION-GENERATED SYNTHETIC DATA.
%
%   Outputs:
%     results/ai_closed_loop_trace.json
%     results/ai_closed_loop_summary.txt
%
%   See also: RUN_FULL_PIPELINE, AI_SUPERVISORY_CONTROL_RECOMMENDER.

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);

% Load environment (.env). Maps VITE_* names; never prints key values.
try
    load_dotenv();
catch
    % .env is optional; the Gemini layer falls back to MOCK without a key
end

P = cip_parameters();
resDir  = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
dataDir = fullfile(root,'data');
baseCsv = fullfile(dataDir,'dairy_cip_synthetic_dataset.csv');
aiCsv   = fullfile(dataDir,'dairy_cip_ai_designed_dataset.csv');
accCsv  = fullfile(dataDir,'dairy_cip_ai_designed_accumulated.csv');
combCsv = fullfile(dataDir,'dairy_cip_combined_dataset.csv');
traceJson = fullfile(resDir,'ai_closed_loop_trace.json');
summaryTxt= fullfile(resDir,'ai_closed_loop_summary.txt');
% Separate, clearly-labelled summary artifacts so each stage's data is explicit.
sumActive = fullfile(resDir,'dataset_summary.json');           % what AI steps read
sumBase   = fullfile(resDir,'dataset_summary_base.json');      % base dataset only
sumComb   = fullfile(resDir,'dataset_summary_combined.json');  % base + AI-designed

if exist(baseCsv,'file') ~= 2
    error('run_ai_closed_loop_study:noBase', ...
        ['Base synthetic dataset not found:\n  %s\n' ...
         'Run run_cip_scenarios (or run_full_pipeline) first.'], baseCsv);
end

% Iterations (kept small for tractable runtime).
NITER = 3;
envIt = getenv('CIP_CLOSED_LOOP_ITERS');
if ~isempty(envIt)
    v = str2double(envIt); if isfinite(v) && v>=1; NITER = round(v); end
end

% Speed up gamultiobj for the iterative loop (classic pipeline keeps defaults).
setenv('CIP_GA_POP','120');
setenv('CIP_GA_MAXGEN','60');

% Fresh accumulation for this study run.
if exist(accCsv,'file')==2; delete(accCsv); end

fprintf('\n################################################################\n');
fprintf('#  AI-SUPERVISED CLOSED-LOOP DIGITAL TWIN (dairy CIP)           #\n');
fprintf('#  Agentic loop in the SIMULATOR only - SYNTHETIC data.         #\n');
fprintf('#  Iterations: %d                                               \n', NITER);
fprintf('################################################################\n');

% Build the model-equation summary once (model is not modified in the loop).
try
    build_model_equation_summary();
catch ME
    fprintf(2,'[closed-loop] equation summary failed: %s\n', ME.message);
end

% Snapshot the BASE dataset summary once, as a clearly-labelled artifact.
setenv('CIP_DATASET_CSV','');   % base dataset
localRunScriptSafe(fullfile(here,'build_dataset_summary.m'), 'build_dataset_summary (base)');
try
    if exist(sumActive,'file')==2; copyfile(sumActive, sumBase); end
catch ME
    fprintf(2,'[closed-loop] base summary snapshot failed: %s\n', ME.message);
end

loopTic = tic;
trace = cell(NITER,1);
prevSel = [];

for it = 1:NITER
    fprintf('\n================ ITERATION %d / %d ================\n', it, NITER);
    entry = struct('iteration', it);

    % --- 1. dataset summary on the COMBINED-SO-FAR feedback ----------
    % The AI context (hypotheses + audit) must reflect the accumulated
    % closed-loop feedback, i.e. base + all AI-designed batches from PRIOR
    % iterations (the current batch is generated below, after this summary).
    % Iter 1 has no prior batches, so the summary is on the base dataset.
    nCtx = NaN;
    if exist(accCsv,'file')==2
        try
            nCtx = localBuildCombined(baseCsv, accCsv, combCsv);  % base + prior batches
            setenv('CIP_DATASET_CSV', combCsv);
        catch ME
            fprintf(2,'[closed-loop] context combine failed: %s\n', ME.message);
        end
    end
    localRunScriptSafe(fullfile(here,'build_dataset_summary.m'), 'build_dataset_summary');
    setenv('CIP_DATASET_CSV','');   % do not leak the context dataset into later steps
    entry.summary_context_rows = nCtx;   % NaN on iter 1 (base dataset only)

    % --- 2. hypotheses (AI proposes; sees the combined-so-far summary) -
    hypN = NaN; hypSrc = 'n/a';
    try
        [~, hypOut] = gemini_hypothesis_generator();
        hypN = hypOut.n_hypotheses; hypSrc = hypOut.source;
    catch ME
        fprintf(2,'[closed-loop] hypothesis generator failed: %s\n', ME.message);
    end

    % --- 3. experiment design (AI proposes; MATLAB clamps) -----------
    batchName = 'n/a'; nScen = 0; designSrc = 'n/a';
    try
        [scen, design] = gemini_experiment_designer();
        nScen = height(scen);
        if isfield(design,'experiment_batch_name'); batchName = char(string(design.experiment_batch_name)); end
        if isfield(design,'source'); designSrc = char(string(design.source)); end
    catch ME
        fprintf(2,'[closed-loop] experiment designer failed: %s\n', ME.message);
    end

    % --- 4. simulate AI-designed scenarios ---------------------------
    nRun = 0; nSucc = 0;
    try
        [~, st] = run_ai_designed_scenarios();
        nRun = st.n; nSucc = st.n_success;
        localAppendCsv(aiCsv, accCsv);   % accumulate across iterations
    catch ME
        fprintf(2,'[closed-loop] AI scenario run failed: %s\n', ME.message);
    end

    % --- build combined dataset (base + accumulated AI-designed) -----
    nComb = NaN;
    try
        nComb = localBuildCombined(baseCsv, accCsv, combCsv);
    catch ME
        fprintf(2,'[closed-loop] combine failed: %s\n', ME.message);
    end

    % --- 5. validate hypotheses (deterministic; pools base + AI) -----
    vsup=NaN; vpar=NaN; vnot=NaN; vinc=NaN;
    try
        [~, vsum] = validate_ai_hypotheses(struct('include_ai_designed',true));
        vsup=vsum.n_supported; vpar=vsum.n_partially; vnot=vsum.n_not_supported; vinc=vsum.n_inconclusive;
    catch ME
        fprintf(2,'[closed-loop] hypothesis validation failed: %s\n', ME.message);
    end

    % --- 5b. rebuild summary on the COMBINED dataset INCLUDING the -----
    % current batch, so the model auditor sees the CURRENT feedback (not just
    % prior batches). Refreshes the active summary + the labelled combined copy.
    if isfinite(nComb) && exist(combCsv,'file')==2
        setenv('CIP_DATASET_CSV', combCsv);
        localRunScriptSafe(fullfile(here,'build_dataset_summary.m'), 'build_dataset_summary (combined, pre-audit)');
        setenv('CIP_DATASET_CSV','');
        try
            if exist(sumActive,'file')==2; copyfile(sumActive, sumComb); end
        catch ME
            fprintf(2,'[closed-loop] combined summary snapshot failed: %s\n', ME.message);
        end
    end

    % --- 6. model audit (AI flags; no parameter change) --------------
    % Reads dataset_summary.json, now reflecting base + ALL AI batches incl. the
    % current one (see step 5b), so the audit reflects the latest feedback.
    nHigh = NaN; auditSrc = 'n/a';
    try
        aud = gemini_model_auditor();
        nHigh = aud.n_high_severity; auditSrc = aud.source;
    catch ME
        fprintf(2,'[closed-loop] model auditor failed: %s\n', ME.message);
    end

    % --- 7. retrain surrogates on the COMBINED dataset ---------------
    if isfinite(nComb) && exist(combCsv,'file')==2
        setenv('CIP_DATASET_CSV', combCsv);
    end
    localRunScriptSafe(fullfile(here,'train_surrogate_models.m'), 'train_surrogate_models (combined)');
    setenv('CIP_DATASET_CSV','');   % restore default for any later standalone run

    % --- 8. recompute Pareto -----------------------------------------
    localRunScriptSafe(fullfile(here,'optimize_cip_pareto.m'), 'optimize_cip_pareto');

    % --- 9. virtual supervisory recommendation -----------------------
    gatePassed=false; researchOnly=true; nPass=NaN; nCand=NaN; sel=struct(); selMetrics=struct();
    try
        rec = ai_supervisory_control_recommender(struct('timestamp', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'))));
        gatePassed = rec.safety_gate.passed; researchOnly = rec.research_only;
        if isfield(rec.safety_gate,'n_passed'); nPass = rec.safety_gate.n_passed; end
        if isfield(rec.safety_gate,'n_candidates'); nCand = rec.safety_gate.n_candidates; end
        if isfield(rec,'selected_recipe'); sel = rec.selected_recipe; end
        if isfield(sel,'predicted_metrics'); selMetrics = sel.predicted_metrics; end
    catch ME
        fprintf(2,'[closed-loop] supervisory recommender failed: %s\n', ME.message);
    end

    % --- assemble iteration trace ------------------------------------
    entry.ai_proposed = struct('n_hypotheses',hypN,'hypotheses_source',hypSrc, ...
        'experiment_batch_name',batchName,'n_candidate_scenarios',nScen,'design_source',designSrc);
    entry.simulator_ran = struct('n_scenarios',nRun,'n_success',nSucc,'n_failed',nRun-nSucc);
    entry.training = struct('combined_rows',nComb);
    entry.hypotheses_supported = struct('n_supported',vsup,'n_partially',vpar, ...
        'n_not_supported',vnot,'n_inconclusive',vinc);
    entry.safety_gate = struct('passed',gatePassed,'n_passed',nPass,'n_candidates',nCand);
    entry.pareto_recommendation = struct('research_only',researchOnly,'metrics',selMetrics);
    entry.pareto_change = localDelta(prevSel, selMetrics);
    entry.remaining_uncertainty = struct('model_audit_high_severity',nHigh, ...
        'note','soil0->COD link and COD-NaOH coupling remain under review until calibration.');
    trace{it} = entry;
    prevSel = selMetrics;

    fprintf(['[closed-loop] iter %d: hyps=%g(%s) scen=%g/%g combined=%g ', ...
        'supported=%g gate_passed=%d research_only=%d audit_high=%g\n'], ...
        it, hypN, hypSrc, nSucc, nRun, nComb, vsup, gatePassed, researchOnly, nHigh);
end

setenv('CIP_GA_POP',''); setenv('CIP_GA_MAXGEN','');   % restore optimizer defaults

%% ----- Save trace + summary -------------------------------------------------
out = struct();
out.study = 'AI-supervised closed-loop digital twin for dairy CIP';
out.data_label = 'simulation-generated synthetic data - NOT real industrial data';
out.governance_note = ['Gemini proposes; deterministic MATLAB validates and decides; ', ...
    'safety gate gates; human approval mandatory; no real-time control.'];
out.n_iterations = NITER;
out.elapsed_seconds = round(toc(loopTic),1);
out.iterations = [trace{:}];
fid = fopen(traceJson,'w');
if fid < 0; error('run_ai_closed_loop_study:fopen','Cannot write %s', traceJson); end
fwrite(fid, jsonencode(out,'PrettyPrint',true), 'char'); fclose(fid);

localWriteLoopSummary(summaryTxt, out);

% Refresh the reproducibility manifest after the study.
try
    build_run_manifest();
catch ME
    fprintf(2,'[closed-loop] manifest failed: %s\n', ME.message);
end

fprintf('\n[run_ai_closed_loop_study] COMPLETE in %.1f s. Trace -> %s\n', out.elapsed_seconds, traceJson);
fprintf('[run_ai_closed_loop_study] Results are SYNTHETIC, proof-of-concept; human approval required.\n');

%% ===== Local functions ======================================================
function localRunScriptSafe(scriptPath, label)
% Run a script in this helper's own (non-static) workspace; never abort the loop.
    try
        run(scriptPath);
    catch ME
        fprintf(2,'[closed-loop] %s FAILED: %s\n', label, ME.message);
    end
end

function localAppendCsv(srcCsv, accCsv)
% Append the latest AI-designed batch to the accumulation file (common columns).
    if exist(srcCsv,'file') ~= 2; return; end
    S = readtable(srcCsv);
    if exist(accCsv,'file')==2
        A = readtable(accCsv);
        common = intersect(A.Properties.VariableNames, S.Properties.VariableNames, 'stable');
        A = [A(:,common); S(:,common)];
    else
        A = S;
    end
    writetable(A, accCsv);
end

function n = localBuildCombined(baseCsv, accCsv, outCsv)
% Combined training set = base synthetic + accumulated AI-designed (common cols).
    B = readtable(baseCsv);
    if exist(accCsv,'file')==2
        A = readtable(accCsv);
        common = intersect(B.Properties.VariableNames, A.Properties.VariableNames, 'stable');
        C = [B(:,common); A(:,common)];
    else
        C = B;
    end
    writetable(C, outCsv);
    n = height(C);
end

function d = localDelta(prev, cur)
% Per-metric change in the selected recipe vs the previous iteration.
    d = struct();
    if isempty(prev) || ~isstruct(prev) || ~isstruct(cur); d.note = 'first iteration (no baseline)'; return; end
    fns = intersect(fieldnames(prev), fieldnames(cur));
    for i = 1:numel(fns)
        a = prev.(fns{i}); b = cur.(fns{i});
        if isnumeric(a) && isnumeric(b) && isscalar(a) && isscalar(b)
            d.(fns{i}) = round(b - a, 4);
        end
    end
    if isempty(fieldnames(d)); d.note = 'no comparable metrics'; end
end

function localWriteLoopSummary(outTxt, out)
    fid = fopen(outTxt,'w');
    if fid < 0; return; end
    cu = onCleanup(@() fclose(fid));
    fprintf(fid,'================================================================\n');
    fprintf(fid,' AI-SUPERVISED CLOSED-LOOP DIGITAL TWIN - STUDY SUMMARY\n');
    fprintf(fid,' (SIMULATION-GENERATED SYNTHETIC DATA; agentic loop in simulator)\n');
    fprintf(fid,'================================================================\n\n');
    fprintf(fid,'Iterations : %d   Elapsed : %.1f s\n', out.n_iterations, out.elapsed_seconds);
    fprintf(fid,'%s\n\n', out.governance_note);
    it = out.iterations;
    for i = 1:numel(it)
        e = it(i);
        fprintf(fid,'---- ITERATION %d ----\n', e.iteration);
        fprintf(fid,'  AI proposed     : %g hypotheses (%s); experiments "%s" x%g (%s)\n', ...
            e.ai_proposed.n_hypotheses, e.ai_proposed.hypotheses_source, ...
            e.ai_proposed.experiment_batch_name, e.ai_proposed.n_candidate_scenarios, e.ai_proposed.design_source);
        fprintf(fid,'  Simulator ran   : %g/%g scenarios succeeded; combined training rows=%g\n', ...
            e.simulator_ran.n_success, e.simulator_ran.n_scenarios, e.training.combined_rows);
        fprintf(fid,'  Hypotheses      : supported=%g partial=%g not=%g inconclusive=%g\n', ...
            e.hypotheses_supported.n_supported, e.hypotheses_supported.n_partially, ...
            e.hypotheses_supported.n_not_supported, e.hypotheses_supported.n_inconclusive);
        fprintf(fid,'  Safety gate     : passed=%d (%g/%g candidates); research_only=%d\n', ...
            e.safety_gate.passed, e.safety_gate.n_passed, e.safety_gate.n_candidates, ...
            e.pareto_recommendation.research_only);
        if isstruct(e.pareto_recommendation.metrics) && isfield(e.pareto_recommendation.metrics,'cleaning_score')
            m = e.pareto_recommendation.metrics;
            fprintf(fid,'  Recommendation  : cleaning=%.2f COD=%.0f water=%.0f energy=%.2f CO2=%.2f\n', ...
                localF(m,'cleaning_score'), localF(m,'COD_mgL'), localF(m,'water_L'), ...
                localF(m,'total_energy_kWh'), localF(m,'CO2eq_kg'));
        end
        fprintf(fid,'  Uncertainty     : model-audit HIGH flags=%g\n\n', e.remaining_uncertainty.model_audit_high_severity);
    end
    fprintf(fid,'CONCLUSION: The loop demonstrates AI-proposed, MATLAB-verified, safety-gated\n');
    fprintf(fid,'decision support in the digital twin. Recommendations remain research-only\n');
    fprintf(fid,'pending calibration with industrial data and food-safety validation.\n');
end

function v = localF(s, f)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)); v = s.(f); else; v = NaN; end
end
