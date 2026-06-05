% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function rec = ai_supervisory_control_recommender(opts)
%AI_SUPERVISORY_CONTROL_RECOMMENDER  Virtual, human-approvable CIP recommendation.
%
%   rec = AI_SUPERVISORY_CONTROL_RECOMMENDER() is the innovative supervisory
%   layer of the study. It does NOT control Simulink in real time and does NOT
%   control any plant. It selects a candidate CIP recipe from the numerically
%   computed Pareto front, runs a DETERMINISTIC safety gate, and (only then) asks
%   Gemini to EXPLAIN the strategy and risks. The numeric decision is made by
%   MATLAB; Gemini never overrides the gate and never sets a value.
%
%   Inputs (via files; override with OPTS fields of the same name):
%       selected_policy_config.json, pareto_solutions.csv, surrogate_metrics.csv,
%       surrogate_models.mat, plausibility_audit.json, model_audit_report.json,
%       ai_hypothesis_validation.csv (optional).
%   OPTS may also set .out_json, .out_txt, .explain (default true).
%
%   DETERMINISTIC SAFETY GATE rejects any candidate with:
%     * cleaning_score < min_cleaning_score (policy hygiene floor, >= 95)
%     * COD_mgL / water_L / total_energy_kWh / CO2eq_kg above a finite policy cap
%     * hygienic_risk above a finite cap (when a hygienic_risk surrogate exists)
%     * any input variable outside P.lb/P.ub
%   The whole recommendation is marked research_only = true when:
%     * a SAFETY-CRITICAL surrogate has held-out R^2 < P.surrogate_r2_floor, or
%     * the model audit reports unresolved HIGH-severity flags.
%
%   Outputs: results/ai_supervisory_recommendation.json (+ .txt).
%   >>> All numbers are SIMULATION-GENERATED SYNTHETIC surrogate predictions.
%   NOT for real-time control or plant deployment without calibration. <<<
%
%   See also: OPTIMIZE_CIP_PARETO, GEMINI_MODEL_AUDITOR, GEMINI_POLICY_TRANSLATOR.

    if nargin < 1 || isempty(opts); opts = struct(); end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    P = cip_parameters();
    resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end

    policyPath = localOpt(opts,'selected_policy_config', fullfile(resDir,'selected_policy_config.json'));
    % Candidate front: prefer the ROBUST (uncertainty-aware) front when present,
    % since its recipes are conservatively feasible (cleaning q05 >= floor) and so
    % can clear the safety shield; otherwise fall back to the mean Pareto front.
    parPath    = localOpt(opts,'pareto_solutions', '');
    if isempty(parPath)
        robPath = fullfile(resDir,'robust_pareto_solutions.csv');
        if exist(robPath,'file')==2; parPath = robPath; else; parPath = fullfile(resDir,'pareto_solutions.csv'); end
    end
    metPath    = localOpt(opts,'surrogate_metrics',     fullfile(resDir,'surrogate_metrics.csv'));
    matPath    = localOpt(opts,'surrogate_models',      fullfile(resDir,'surrogate_models.mat'));
    audPath    = localOpt(opts,'plausibility_audit',    fullfile(resDir,'plausibility_audit.json'));
    modPath    = localOpt(opts,'model_audit_report',    fullfile(resDir,'model_audit_report.json'));
    hypPath    = localOpt(opts,'hypothesis_validation', fullfile(resDir,'ai_hypothesis_validation.csv'));
    outJson    = localOpt(opts,'out_json', fullfile(resDir,'ai_supervisory_recommendation.json'));
    outTxt     = localOpt(opts,'out_txt',  fullfile(resDir,'ai_supervisory_recommendation.txt'));
    doExplain  = localOpt(opts,'explain', true);

    if exist(parPath,'file') ~= 2
        error('ai_supervisory_control_recommender:noPareto', ...
            'Pareto solutions not found:\n  %s\nRun optimize_cip_pareto first.', parPath);
    end
    Pa = localLoadFront(parPath);
    if isempty(Pa); error('ai_supervisory_control_recommender:emptyPareto','Pareto file is empty.'); end
    rec_source_front = parPath;

    % ---- Policy constraints + weights -----------------------------------
    [con, weights, profileName] = localLoadPolicy(policyPath, P);

    % ---- Surrogate R^2 for critical targets -----------------------------
    % When the policy enforces a finite max_hygienic_risk, the hygienic_risk
    % surrogate becomes safety-critical too (its reliability gates the cap).
    [r2map, lowR2] = localCriticalR2(metPath, P, con);

    % ---- Optional hygienic_risk surrogate (for the max_hygienic_risk cap)-
    [hygMdl, predictors] = localLoadHygModel(matPath);

    % ---- Model-audit high severity --------------------------------------
    [nHigh, auditSummary] = localAuditHigh(modPath);

    % ---- Plausibility-audit high-severity flags (dataset-level) ---------
    nPlausHigh = localPlausHigh(audPath);

    % ---- Hypothesis-validation summary (optional context) ---------------
    hypSummary = localHypSummary(hypPath);

    % ---- Global research_only triggers (deterministic) ------------------
    researchOnly = false; globalFails = {};
    if ~isempty(lowR2)
        researchOnly = true;
        globalFails{end+1} = sprintf(['Critical surrogate R^2 below floor %.2f: %s ', ...
            '(predictions not reliable enough for a binding recommendation).'], ...
            P.surrogate_r2_floor, strjoin(lowR2, ', '));
    end
    if nHigh > 0
        researchOnly = true;
        globalFails{end+1} = sprintf(['Model audit reports %d unresolved HIGH-severity ', ...
            'flag(s); recommendation is research-only until resolved.'], nHigh);
    end
    if nPlausHigh > 0
        researchOnly = true;
        globalFails{end+1} = sprintf(['Plausibility audit reports %d HIGH-severity ', ...
            'flag(s) on the synthetic dataset; recommendation is research-only.'], nPlausHigh);
    end

    % ---- Per-candidate deterministic safety gate ------------------------
    nC = height(Pa);
    passedMask = false(nC,1);
    failedList = cell(nC,1);
    hygVals    = nan(nC,1);
    for i = 1:nC
        [ok, fails, hr] = localGateCandidate(Pa(i,:), P, con, hygMdl, predictors);
        passedMask(i) = ok; failedList{i} = fails; hygVals(i) = hr;
    end

    % ---- Rank PASSING candidates, pick the best that CLEARS the shield --
    % Candidates are ranked by the policy-weighted score; the recommendation is
    % the highest-ranked one that ALSO clears the deterministic safety_shield
    % (conservative uncertainty bounds). The shield is mandatory and cannot be
    % bypassed: if none clears it, the top-by-score recipe is shown but marked
    % gate_passed=false.
    rankedIdx = localRankByScore(Pa, passedMask, weights);
    shieldOpts = struct('policy_path',policyPath,'model_audit_path',modPath, ...
                        'metrics_csv',metPath,'audit_high',nHigh);
    try
        shieldOpts.unc = load(fullfile(root,'models','uncertainty_surrogates.mat'));
    catch
        % uncertainty surrogates optional; shield falls back to point estimates
    end
    selIdx = []; topIdx = []; selShield = [];
    for jj = 1:numel(rankedIdx)
        ci = rankedIdx(jj);
        sh = safety_shield(localRowToRecipe(Pa(ci,:), P), shieldOpts);
        if isempty(topIdx); topIdx = ci; selShield = sh; end   % best-by-score fallback
        if sh.gate_passed; selIdx = ci; selShield = sh; break; end
    end
    shieldCleared = ~isempty(selIdx);
    if ~shieldCleared; selIdx = topIdx; end                    % may be [] if none feasible

    rec = struct();
    rec.mode = 'virtual_supervisory_control_recommendation';
    rec.not_for_real_time_control = true;
    rec.profile = profileName;
    [~, frontName, frontExt] = fileparts(rec_source_front);
    rec.candidate_front = [frontName frontExt];   % robust vs mean Pareto source
    rec.timestamp = localOpt(opts,'timestamp', '');   % stamped by caller if desired
    rec.data_label = 'simulation-generated synthetic data - NOT real industrial data';

    safetyPassed = shieldCleared;       % gate passes only if a recipe cleared the shield
    if ~isempty(selIdx)
        rec.selected_recipe = localRecipe(Pa(selIdx,:), P, hygVals(selIdx), weights);
        % Unify reported metrics with the safety shield's predictions so the recipe
        % and the shield never disagree (e.g. hygienic_risk). The shield's means
        % become predicted_metrics; its lower/upper become conservative_bounds.
        if ~isempty(selShield) && isfield(selShield,'predicted') && isstruct(selShield.predicted)
            fn = fieldnames(selShield.predicted);
            for ii = 1:numel(fn)
                rec.selected_recipe.predicted_metrics.(fn{ii}) = round(selShield.predicted.(fn{ii}).mean,4);
            end
            rec.selected_recipe.conservative_bounds = selShield.predicted;   % mean/lower/upper
            rec.selected_recipe.metrics_basis = selShield.basis;
        end
    else
        rec.selected_recipe = struct();
        globalFails{end+1} = 'No Pareto candidate passed the deterministic safety gate.';
    end
    if ~isempty(selIdx) && ~shieldCleared
        globalFails{end+1} = 'No candidate cleared the safety shield; top-ranked recipe shown (shield-vetoed).';
    end

    % rejected candidates (those that failed at least one check), capped
    rej = {};
    for i = 1:nC
        if ~passedMask(i)
            rej{end+1} = struct( ...
                'row', i, ...
                'cleaning_score', round(localCol(Pa(i,:),'cleaning_score'),3), ...
                'COD_mgL', round(localCol(Pa(i,:),'COD_mgL'),3), ...
                'water_L', round(localCol(Pa(i,:),'water_L'),3), ...
                'total_energy_kWh', round(localCol(Pa(i,:),'total_energy_kWh'),3), ...
                'CO2eq_kg', round(localCol(Pa(i,:),'CO2eq_kg'),3), ...
                'failed_checks', failedList(i)); %#ok<AGROW>
        end
    end
    if numel(rej) > 25; rej = rej(1:25); end
    rec.rejected_candidates = rej;

    rec.safety_gate = struct('passed', safetyPassed, ...
        'n_candidates', nC, 'n_passed', sum(passedMask), 'n_rejected', sum(~passedMask), ...
        'failed_checks', {globalFails}, 'advisories', {{}}, ...
        'constraints_applied', con, 'critical_surrogate_R2', r2map, ...
        'r2_basis', 'point_estimate', 'r2_floor', P.surrogate_r2_floor);

    rec.human_approval_required = true;       % governance: always
    rec.research_only = researchOnly;
    rec.model_audit_high_severity = nHigh;
    rec.plausibility_high_severity = nPlausHigh;
    rec.hypothesis_validation = hypSummary;

    % ---- Open validation requirements -----------------------------------
    rec.open_validation_requirements = localOpenReqs(modPath);

    % ---- MANDATORY deterministic safety shield (AI cannot bypass) -------
    % selShield was computed during shield-aware selection above; record it and
    % fold any (top-by-score) violations into the gate when nothing cleared it.
    if ~isempty(selShield)
        rec.safety_shield = selShield;
        if ~selShield.gate_passed && ~isempty(selShield.violations)
            extra = cellfun(@(s) ['shield: ' s], selShield.violations, 'UniformOutput', false);
            rec.safety_gate.failed_checks = [rec.safety_gate.failed_checks, extra];
        end
        % Propagate the shield's research-only advisories into the gate so the
        % gate, the explanation and the dossier all tell the SAME story.
        if isfield(selShield,'advisories'); rec.safety_gate.advisories = selShield.advisories; end
        % When the shield judged the recipe with CONSERVATIVE uncertainty bounds,
        % the authoritative critical R^2 is the QUANTILE-surrogate R^2, not the
        % point-surrogate R^2 (which would otherwise overstate reliability).
        if isfield(selShield,'basis') && strcmp(selShield.basis,'uncertainty_conservative') ...
                && isfield(selShield,'surrogate_R2') && isstruct(selShield.surrogate_R2)
            rec.safety_gate.critical_surrogate_R2 = selShield.surrogate_R2;
            rec.safety_gate.r2_basis = selShield.basis;
            if isfield(selShield,'surrogate_metrics_source')
                rec.safety_gate.r2_source = selShield.surrogate_metrics_source;
            end
        end
        rec.research_only = rec.research_only || selShield.research_only;
    else
        rec.safety_shield = struct('gate_passed', false, 'research_only', true, ...
            'basis','none','note', 'No recipe passed candidate selection; shield not applicable.');
    end

    % ---- Gemini explanation (governed; never changes numbers) -----------
    [mgr, eng, usedMock] = localExplain(rec, auditSummary, profileName, doExplain);
    % Governance: neutralize any operational directives in the free-text summaries
    % before they are stored/written (defense-in-depth with the system prompt; the
    % whole study is research-only on SYNTHETIC data).
    rec.manager_summary  = gemini_sanitize_report(mgr, false);
    rec.engineer_summary = gemini_sanitize_report(eng, false);
    rec.explanation_source = ternary(usedMock,'MOCK_fallback','gemini_live');
    rec.governance_note = ['Deterministic MATLAB safety gate decides feasibility; ', ...
        'Gemini only explains. Human approval mandatory; not for real-time control.'];

    % ---- Save -----------------------------------------------------------
    fid = fopen(outJson,'w');
    if fid < 0; error('ai_supervisory_control_recommender:fopen','Cannot write %s', outJson); end
    fwrite(fid, jsonencode(rec,'PrettyPrint',true), 'char'); fclose(fid);
    localWriteTxt(outTxt, rec);

    fprintf(['[ai_supervisory_control_recommender] gate_passed=%d research_only=%d ', ...
        'passed=%d/%d -> %s\n'], safetyPassed, researchOnly, sum(passedMask), nC, outJson);
end

% ======================================================================
function Pa = localLoadFront(parPath)
% Load a candidate front. If it is a ROBUST front (has {tgt}_mean columns),
% map them to the point names the recommender expects. 'preserve' avoids the
% benign "headers modified" warning on valid headers.
    Pa = readtable(parPath, 'Delimiter',',', 'VariableNamingRule','preserve');
    vn = Pa.Properties.VariableNames;
    tg = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg','cleaning_score','EHPI','hygienic_risk'};
    for i = 1:numel(tg)
        m = [tg{i} '_mean'];
        if ismember(m, vn) && ~ismember(tg{i}, vn)
            Pa.(tg{i}) = Pa.(m);
        end
    end
end

function [con, weights, profileName] = localLoadPolicy(policyPath, P)
% Read constraints + weights; default to a balanced profile if missing.
    con = struct('min_cleaning_score',max(95,P.min_cleaning_score), ...
        'max_COD_mgL',NaN,'max_hygienic_risk',NaN,'max_water_L',NaN, ...
        'max_total_energy_kWh',NaN,'max_CO2eq_kg',NaN);
    weights = struct('water_L',0.25,'total_energy_kWh',0.20,'COD_mgL',0.25, ...
        'CO2eq_kg',0.20,'cleaning_score',0.10);
    profileName = 'unspecified';
    if exist(policyPath,'file') ~= 2; return; end
    try
        cfg = jsondecode(fileread(policyPath));
        if isfield(cfg,'profile') && ~isempty(cfg.profile); profileName = char(cfg.profile); end
        if isfield(cfg,'constraints')
            con.min_cleaning_score = max(95, localScalar(cfg.constraints,'min_cleaning_score', con.min_cleaning_score));
            for f = {'max_COD_mgL','max_hygienic_risk','max_water_L','max_total_energy_kWh','max_CO2eq_kg'}
                v = localScalar(cfg.constraints, f{1}, NaN);
                if isfinite(v) && v > 0; con.(f{1}) = v; end
            end
        end
        if isfield(cfg,'objective_weights')
            for f = fieldnames(weights).'
                wv = localScalar(cfg.objective_weights, f{1}, NaN);
                if isfinite(wv); weights.(f{1}) = wv; end
            end
        end
    catch ME
        warning('ai_supervisory_control_recommender:policy','Policy read failed: %s', ME.message);
    end
end

% ======================================================================
function [r2map, lowR2] = localCriticalR2(metPath, P, con)
% Map critical-target R^2 and list those below the floor. hygienic_risk is
% added to the critical set only when the policy enforces a finite cap on it.
    r2map = struct(); lowR2 = {};
    crit = P.critical_targets;
    if nargin >= 3 && isstruct(con) && isfield(con,'max_hygienic_risk') ...
            && isfinite(con.max_hygienic_risk) && ~ismember('hygienic_risk', crit)
        crit = [crit, {'hygienic_risk'}];
    end
    if exist(metPath,'file') ~= 2; return; end
    try
        M = readtable(metPath, 'VariableNamingRule','preserve');
        for i = 1:numel(crit)
            tgt = crit{i};
            idx = find(strcmp(string(M.target), tgt), 1);
            if ~isempty(idx)
                r2 = M.R2(idx);
                r2map.(tgt) = round(r2,4);
                if ~(isfinite(r2) && r2 >= P.surrogate_r2_floor)
                    lowR2{end+1} = tgt; %#ok<AGROW>
                end
            else
                lowR2{end+1} = tgt; %#ok<AGROW> % missing metric => treat as unreliable
            end
        end
    catch ME
        warning('ai_supervisory_control_recommender:metrics','Metrics read failed: %s', ME.message);
    end
end

% ======================================================================
function [hygMdl, predictors] = localLoadHygModel(matPath)
% Load the hygienic_risk surrogate if present (else [] => cap is informational).
    hygMdl = []; predictors = {};
    if exist(matPath,'file') ~= 2; return; end
    try
        S = load(matPath);
        if isfield(S,'predictors'); predictors = S.predictors; end
        if isfield(S,'models') && isfield(S.models,'hygienic_risk')
            hygMdl = S.models.hygienic_risk;
        end
    catch
        % leave empty (graceful)
    end
end

% ======================================================================
function [nHigh, summaryText] = localAuditHigh(modPath)
    nHigh = 0; summaryText = '';
    if exist(modPath,'file') ~= 2; return; end
    try
        A = jsondecode(fileread(modPath));
        if isfield(A,'n_high_severity')
            nHigh = A.n_high_severity;
        elseif isfield(A,'model_audit_flags')
            F = A.model_audit_flags; if iscell(F); F = [F{:}]; end
            nHigh = sum(arrayfun(@(f) isfield(f,'severity') && strcmpi(char(string(f.severity)),'high'), F));
        end
        if isfield(A,'manuscript_limitations_text')
            summaryText = char(string(A.manuscript_limitations_text));
        end
    catch
        % leave defaults
    end
end

% ======================================================================
function n = localPlausHigh(audPath)
% Count HIGH-severity flags in the prior plausibility audit (dataset-level).
    n = 0;
    if exist(audPath,'file') ~= 2; return; end
    try
        A = jsondecode(fileread(audPath));
        if isfield(A,'plausibility_flags')
            F = A.plausibility_flags; if iscell(F); F = [F{:}]; end
            n = sum(arrayfun(@(f) isfield(f,'severity') && ...
                strcmpi(char(string(f.severity)),'high'), F));
        end
    catch
        n = 0;
    end
end

% ======================================================================
function hyp = localHypSummary(hypPath)
    hyp = struct('available',false);
    if exist(hypPath,'file') ~= 2; return; end
    try
        T = readtable(hypPath, 'Delimiter',',', 'TextType','string', 'VariableNamingRule','preserve');
        hyp.available = true;
        s = T.support;
        hyp.n_total       = height(T);
        hyp.n_supported   = sum(s=="supported");
        hyp.n_partially   = sum(s=="partially_supported");
        hyp.n_not_supported = sum(s=="not_supported");
        hyp.n_inconclusive  = sum(s=="inconclusive");
    catch
        hyp.available = false;
    end
end

% ======================================================================
function [ok, fails, hr] = localGateCandidate(row, P, con, hygMdl, predictors)
    fails = {}; tol = 1e-6;
    % (1) input bounds
    for k = 1:numel(P.var_names)
        nm = P.var_names{k};
        if ismember(nm, row.Properties.VariableNames)
            v = row.(nm);
            if v < P.lb(k)-tol || v > P.ub(k)+tol
                fails{end+1} = sprintf('%s=%.4g outside [%.4g, %.4g]', nm, v, P.lb(k), P.ub(k)); %#ok<AGROW>
            end
        end
    end
    % (2) hygiene floor
    cs = localCol(row,'cleaning_score');
    if isfinite(cs) && cs < con.min_cleaning_score
        fails{end+1} = sprintf('cleaning_score=%.2f < floor %.2f', cs, con.min_cleaning_score);
    end
    % (3) environmental caps (only when finite)
    fails = localCap(fails, row, 'COD_mgL',          con.max_COD_mgL,          'mg/L');
    fails = localCap(fails, row, 'water_L',          con.max_water_L,          'L');
    fails = localCap(fails, row, 'total_energy_kWh', con.max_total_energy_kWh, 'kWh');
    fails = localCap(fails, row, 'CO2eq_kg',         con.max_CO2eq_kg,         'kg');
    % (4) hygienic risk via surrogate (if available)
    hr = NaN;
    if ~isempty(hygMdl) && ~isempty(predictors)
        try
            x = zeros(1,numel(predictors));
            for k = 1:numel(predictors)
                if ismember(predictors{k}, row.Properties.VariableNames)
                    x(k) = row.(predictors{k});
                end
            end
            hr = min(1, max(0, predict(hygMdl, array2table(x,'VariableNames',predictors))));
        catch
            hr = NaN;
        end
    end
    if isfinite(con.max_hygienic_risk) && isfinite(hr) && hr > con.max_hygienic_risk
        fails{end+1} = sprintf('hygienic_risk=%.3f > cap %.3f', hr, con.max_hygienic_risk);
    end
    ok = isempty(fails);
end

function fails = localCap(fails, row, name, cap, unit)
    if isfinite(cap)
        v = localCol(row, name);
        if isfinite(v) && v > cap
            fails{end+1} = sprintf('%s=%.4g > cap %.4g %s', name, v, cap, unit);
        end
    end
end

% ======================================================================
function order = localRankByScore(Pa, passedMask, weights)
% Rank passing candidates by weighted normalized score (best first; cleaning
% maximized). Returns row indices into Pa, ascending by score.
    order = [];
    sel = find(passedMask);
    if isempty(sel); return; end
    sub = Pa(sel,:);
    nW = localNorm(localCol(sub,'water_L'));
    nE = localNorm(localCol(sub,'total_energy_kWh'));
    nC = localNorm(localCol(sub,'COD_mgL'));
    n2 = localNorm(localCol(sub,'CO2eq_kg'));
    cC = 1 - localNorm(localCol(sub,'cleaning_score'));
    wv = [weights.water_L, weights.total_energy_kWh, weights.COD_mgL, weights.CO2eq_kg, weights.cleaning_score];
    wv = wv / max(sum(wv), eps);
    score = wv(1)*nW + wv(2)*nE + wv(3)*nC + wv(4)*n2 + wv(5)*cC;
    [~,o] = sort(score, 'ascend');
    order = sel(o);
end

function r = localRowToRecipe(row, P)
% Convert a Pareto-solutions row to a recipe struct of the decision variables.
    r = struct();
    for k = 1:numel(P.var_names)
        nm = P.var_names{k};
        if ismember(nm, row.Properties.VariableNames)
            r.(nm) = localCol(row, nm);
        end
    end
end

% ======================================================================
function r = localRecipe(row, P, hr, weights)
    r = struct();
    for k = 1:numel(P.var_names)
        nm = P.var_names{k};
        if ismember(nm, row.Properties.VariableNames); r.(nm) = round(row.(nm),4); end
    end
    r.soil0_note = 'soil0 is a fixed uncertainty condition, not an operator setpoint.';
    pm = struct();
    for f = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg','cleaning_score','EHPI'}
        v = localCol(row, f{1}); if isfinite(v); pm.(f{1}) = round(v,3); end
    end
    if isfinite(hr); pm.hygienic_risk = round(hr,4); end
    r.predicted_metrics = pm;
    r.selection_weights = weights;
    if ismember('selection_label', row.Properties.VariableNames)
        r.pareto_label = char(string(row.selection_label));
    end
    r.prediction_basis = 'ML surrogate over synthetic simulation (not measured)';
end

% ======================================================================
function [mgr, eng, usedMock] = localExplain(rec, auditSummary, profileName, doExplain)
% Ask Gemini to EXPLAIN (not decide). Falls back to a deterministic summary.
    usedMock = true; mgr = ''; eng = '';
    payload = struct('profile',profileName,'research_only',rec.research_only, ...
        'safety_gate',rec.safety_gate,'selected_recipe',rec.selected_recipe, ...
        'model_audit_high_severity',rec.model_audit_high_severity);
    payloadTxt = jsonencode(payload,'PrettyPrint',true);

    if doExplain
        sys = strjoin({ ...
            'You explain a CIP supervisory-control RECOMMENDATION already decided by', ...
            'deterministic MATLAB code. You do NOT change any number or override the gate.', ...
            'RULES:', ...
            '1. Use ONLY the provided numbers; data are simulation-generated synthetic.', ...
            '2. Never present this as ready for real-time control or plant deployment.', ...
            '3. If research_only is true, say so plainly and explain why.', ...
            '4. The R^2 in safety_gate.critical_surrogate_R2 are measured on the basis', ...
            '   safety_gate.r2_basis. If any are below safety_gate.r2_floor, you MUST', ...
            '   say so and must NOT claim all critical R^2 pass.', ...
            '5. List every entry of safety_gate.advisories as a research-only reason.', ...
            '6. Return VALID JSON ONLY: {"manager_summary":"...","engineer_summary":"..."}', ...
            '   manager_summary: 3-5 sentences, non-technical, decision-oriented.', ...
            '   engineer_summary: 3-6 sentences, technical, references the gate/caps,', ...
            '   the r2_basis, and the advisories.'}, newline);
        usr = strjoin({'RECOMMENDATION CONTEXT (JSON):', payloadTxt, '', ...
            sprintf('MODEL AUDIT NOTE: %s', auditSummary)}, newline);
        [txt, info] = gemini_call(sys, usr, struct('json_only',true,'temperature',0.3,'max_tokens',4096));
        if info.ok
            try
                j = jsondecode(regexprep(regexprep(char(txt),'^\s*```[a-zA-Z]*\s*',''),'\s*```\s*$',''));
                if isfield(j,'manager_summary');  mgr = char(string(j.manager_summary)); end
                if isfield(j,'engineer_summary'); eng = char(string(j.engineer_summary)); end
                if ~isempty(mgr) && ~isempty(eng); usedMock = false; end
            catch
                usedMock = true;
            end
        end
    end
    if usedMock
        [mgr, eng] = localMockExplain(rec, profileName);
    end
end

function [mgr, eng] = localMockExplain(rec, profileName)
    ro = ''; if rec.research_only; ro = ' This recommendation is RESEARCH-ONLY due to surrogate/model-audit caveats.'; end
    % Build an advisory clause from the gate so the summary never overstates R^2.
    advTxt = '';
    if isfield(rec.safety_gate,'advisories') && ~isempty(rec.safety_gate.advisories)
        adv = rec.safety_gate.advisories; if ~iscell(adv); adv = {adv}; end
        advTxt = sprintf(' Research-only advisories: %s.', strjoin(cellfun(@(s) char(string(s)), adv, 'UniformOutput', false), '; '));
    end
    r2basis = 'point_estimate';
    if isfield(rec.safety_gate,'r2_basis'); r2basis = rec.safety_gate.r2_basis; end
    if rec.safety_gate.passed
        sr = rec.selected_recipe;
        cs = NaN; if isfield(sr,'predicted_metrics') && isfield(sr.predicted_metrics,'cleaning_score'); cs = sr.predicted_metrics.cleaning_score; end
        mgr = sprintf(['[MOCK] For the %s context, the safety gate accepted %d of %d ', ...
            'candidate recipes and selected one meeting the hygiene floor (predicted ', ...
            'cleaning %.1f%%).%s Human approval is required; figures are synthetic.'], ...
            profileName, rec.safety_gate.n_passed, rec.safety_gate.n_candidates, cs, ro);
        eng = sprintf(['[MOCK] The selected recipe cleared all HARD deterministic checks ', ...
            '(input bounds, hygiene floor and any finite environmental/hygienic caps) under ', ...
            'conservative bounds. Critical surrogate R^2 are reported on the "%s" basis and ', ...
            'compared to the %.2f floor; not all necessarily pass.%s%s Verify against plant data first.'], ...
            r2basis, rec.safety_gate.r2_floor, advTxt, ro);
    else
        mgr = sprintf(['[MOCK] For the %s context, NO candidate passed the deterministic ', ...
            'safety gate, so no recipe is recommended.%s Human review required.'], profileName, ro);
        eng = sprintf(['[MOCK] All candidates violated at least one gate check (hygiene floor ', ...
            'or a finite policy cap), or a global blocker applies (see safety_gate.failed_checks).%s%s'], advTxt, ro);
    end
end

% ======================================================================
function reqs = localOpenReqs(modPath)
    reqs = {'Calibrate model coefficients against industrial/literature CIP data.'; ...
            'Validate cleaning_score against microbiological / ATP measurements.'; ...
            'Independently verify mass/energy balances and effluent COD chemistry.'};
    if exist(modPath,'file')==2
        try
            A = jsondecode(fileread(modPath));
            if isfield(A,'minimum_real_measurements_needed') && ~isempty(A.minimum_real_measurements_needed)
                extra = A.minimum_real_measurements_needed;
                if ischar(extra); extra = {extra}; elseif isstring(extra); extra = cellstr(extra); end
                if iscell(extra)
                    for i = 1:numel(extra); reqs{end+1} = char(string(extra{i})); end %#ok<AGROW>
                end
            end
        catch
            % keep defaults
        end
    end
end

% ======================================================================
function localWriteTxt(outTxt, rec)
    fid = fopen(outTxt,'w');
    if fid < 0; return; end
    cu = onCleanup(@() fclose(fid));
    fprintf(fid,'================================================================\n');
    fprintf(fid,' DAIRY CIP - VIRTUAL SUPERVISORY CONTROL RECOMMENDATION\n');
    fprintf(fid,' (SIMULATION-GENERATED SYNTHETIC DATA - NOT for real-time control)\n');
    fprintf(fid,'================================================================\n\n');
    fprintf(fid,'Profile              : %s\n', rec.profile);
    fprintf(fid,'Safety gate passed   : %d\n', rec.safety_gate.passed);
    fprintf(fid,'Research-only        : %d\n', rec.research_only);
    fprintf(fid,'Human approval req.  : %d\n', rec.human_approval_required);
    fprintf(fid,'Candidates passed    : %d / %d\n\n', rec.safety_gate.n_passed, rec.safety_gate.n_candidates);
    if rec.safety_gate.passed && isfield(rec.selected_recipe,'predicted_metrics')
        fprintf(fid,'---- SELECTED RECIPE (synthetic surrogate prediction) ----\n');
        pm = rec.selected_recipe.predicted_metrics;
        fn = fieldnames(pm);
        for i = 1:numel(fn); fprintf(fid,'  %-18s : %g\n', fn{i}, pm.(fn{i})); end
        fprintf(fid,'\n');
    end
    if ~isempty(rec.safety_gate.failed_checks)
        fprintf(fid,'---- GLOBAL GATE NOTES ----\n');
        fc = rec.safety_gate.failed_checks;
        for i = 1:numel(fc); fprintf(fid,'  [!] %s\n', fc{i}); end
        fprintf(fid,'\n');
    end
    fprintf(fid,'---- MANAGER SUMMARY ----\n%s\n\n', rec.manager_summary);
    fprintf(fid,'---- ENGINEER SUMMARY ----\n%s\n\n', rec.engineer_summary);
    fprintf(fid,'---- OPEN VALIDATION REQUIREMENTS ----\n');
    for i = 1:numel(rec.open_validation_requirements)
        fprintf(fid,'  - %s\n', rec.open_validation_requirements{i});
    end
end

% ===== small helpers =====================================================
function v = localCol(row, name)
    v = NaN;
    if ismember(name, row.Properties.VariableNames)
        x = row.(name);
        if istable(x) || iscell(x); x = x{1}; end
        if isnumeric(x) && ~isempty(x); v = double(x(1)); end
    end
end

function y = localNorm(x)
    x = x(:); lo = min(x); hi = max(x);
    if hi - lo <= eps; y = zeros(size(x)); else; y = (x - lo)/(hi - lo); end
end

function v = localScalar(s, field, default)
    v = default;
    if isstruct(s) && isfield(s, field)
        x = s.(field);
        if isnumeric(x) && isscalar(x); v = x;
        elseif isnumeric(x) && ~isempty(x); v = x(1); end
    end
end

function v = localOpt(opts, field, default)
    if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
        v = opts.(field);
    else
        v = default;
    end
end

function out = ternary(c,a,b)
    if c; out = a; else; out = b; end
end
