% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function dossier = build_ai_decision_dossier(opts)
%BUILD_AI_DECISION_DOSSIER  Traceable human-in-the-loop decision dossier.
%
%   dossier = BUILD_AI_DECISION_DOSSIER() aggregates the study artifacts into a
%   single, reviewable dossier (results/ai_decision_dossier.md and .json) that a
%   human decision-maker can read end-to-end: run identity, data provenance,
%   surrogate accuracy, AI hypotheses and their deterministic validation, the
%   model audit, the active policy, the virtual supervisory recommendation, the
%   safety gate, limitations, and the real measurements required before any
%   operational use.
%
%   OPTS (optional): .run_id, .out_md, .out_json.
%
%   This is decision SUPPORT, not a decision. Every figure is SIMULATION-
%   GENERATED SYNTHETIC data; nothing here is validated for plant deployment.
%
%   See also: BUILD_RUN_MANIFEST, AI_SUPERVISORY_CONTROL_RECOMMENDER.

    if nargin < 1 || isempty(opts); opts = struct(); end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
    outMd   = localOpt(opts,'out_md',   fullfile(resDir,'ai_decision_dossier.md'));
    outJson = localOpt(opts,'out_json', fullfile(resDir,'ai_decision_dossier.json'));

    % ---- Manifest (run id, row counts, gemini mode) ---------------------
    manPath = fullfile(resDir,'run_manifest.json');
    if exist(manPath,'file')==2
        manifest = jsondecode(fileread(manPath));
    else
        manifest = build_run_manifest(struct('run_id', localOpt(opts,'run_id','')));
    end
    runId = manifest.run_id;
    if isfield(opts,'run_id') && ~isempty(opts.run_id); runId = opts.run_id; end

    % ---- Load artifacts (all optional / guarded) ------------------------
    metrics   = localReadTable(fullfile(resDir,'surrogate_metrics.csv'));
    hypDoc    = localReadJson(fullfile(resDir,'ai_hypotheses.json'));
    hypVal    = localReadTable(fullfile(resDir,'ai_hypothesis_validation.csv'));
    modelAud  = localReadJson(fullfile(resDir,'model_audit_report.json'));
    policy    = localReadJson(fullfile(resDir,'selected_policy_config.json'));
    superv    = localReadJson(fullfile(resDir,'ai_supervisory_recommendation.json'));
    uncMet    = localReadTable(fullfile(resDir,'uncertainty_surrogate_metrics.csv'));
    cfTbl     = localReadTable(fullfile(resDir,'counterfactual_cip_results.csv'));
    robTbl    = localReadTable(fullfile(resDir,'robust_pareto_solutions.csv'));

    % ====================================================================
    % Build the machine-readable aggregate
    % ====================================================================
    dossier = struct();
    dossier.run_id = runId;
    dossier.generated = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    dossier.data_source = 'simulation-generated synthetic data (mechanistic Simulink twin, proof-of-concept)';
    dossier.data_label = 'NOT real industrial data; not calibrated; not microbiologically validated';
    dossier.scenario_count = manifest.row_counts.dataset_rows;
    dossier.gemini_mode = manifest.gemini_mode;
    dossier.gemini_model = manifest.gemini_model;
    dossier.artifact_versions = manifest.artifacts;
    dossier.framing = ['This project implements an AI-supervised, self-explaining digital twin ', ...
        'for sustainable dairy CIP decision support. The generative-AI layer is extended ', ...
        'beyond post-hoc explanation to support hypothesis generation, active simulation ', ...
        'design, model plausibility auditing, policy formalization, virtual supervisory ', ...
        'control recommendation, and traceable human-in-the-loop decision dossiers. Direct ', ...
        'real-time process control is explicitly excluded until calibration with industrial ', ...
        'data, microbiological validation, and certified safety constraints are available.'];

    dossier.surrogate_metrics = localMetricsStruct(metrics);
    dossier.uncertainty       = localUncStruct(uncMet);
    dossier.hypotheses        = localHypStruct(hypDoc);
    dossier.hypothesis_validation = localHypValStruct(hypVal);
    dossier.model_audit       = localAuditStruct(modelAud);
    dossier.policy            = localPolicyStruct(policy);
    dossier.supervisory_recommendation = localSupervStruct(superv);
    dossier.safety_shield     = localShieldStruct(superv);
    dossier.robust_optimization = localRobustStruct(robTbl);
    dossier.counterfactual_alternatives = localCfStruct(cfTbl);
    dossier.limitations = { ...
        'Uncalibrated proof-of-concept coefficients; synthetic data only.'; ...
        'Effluent COD is an organic-load proxy tied to cumulative soil removal, not a measured laboratory COD assay.'; ...
        'cleaning_score is a soil-based proxy, not a microbiological measurement.'; ...
        'EHPI is a proposed index, not a regulatory standard.'; ...
        'Gemini cannot verify mass/energy balances; it is never ground truth.'; ...
        'Not for operational control without calibration and food-safety validation.'};
    dossier.real_data_needed_before_operational_use = localRealDataNeeds(modelAud);
    dossier.governance = struct( ...
        'gemini_used_for','hypotheses, experiment design, auditing, policy formalization, explanation', ...
        'gemini_never_used_for','real-time control, Simulink solver, gamultiobj, ground truth', ...
        'numeric_decisions_by','deterministic MATLAB code', ...
        'human_approval_required', true);

    fid = fopen(outJson,'w');
    if fid < 0; error('build_ai_decision_dossier:fopen','Cannot write %s', outJson); end
    fwrite(fid, jsonencode(dossier,'PrettyPrint',true), 'char'); fclose(fid);

    % ====================================================================
    % Build the human-readable markdown
    % ====================================================================
    localWriteMarkdown(outMd, dossier, manifest);

    fprintf('[build_ai_decision_dossier] run_id=%s -> %s (+ .json)\n', runId, outMd);
end

% ======================================================================
function s = localMetricsStruct(T)
    s = struct('available', false, 'targets', {{}}, 'R2', []);
    if isempty(T) || ~ismember('target', T.Properties.VariableNames); return; end
    s.available = true;
    s.targets = cellstr(string(T.target));
    s.R2 = round(T.R2(:).',4);
    if ismember('RMSE', T.Properties.VariableNames); s.RMSE = round(T.RMSE(:).',4); end
end

function s = localUncStruct(T)
% Uncertainty-aware surrogate metrics (coverage + interval width per target).
    s = struct('available', false);
    if isempty(T) || ~ismember('target', T.Properties.VariableNames); return; end
    s.available = true;
    s.targets = cellstr(string(T.target));
    if ismember('R2', T.Properties.VariableNames);                  s.R2 = round(T.R2(:).',4); end
    if ismember('coverage_90', T.Properties.VariableNames);         s.coverage_90 = round(T.coverage_90(:).',4); end
    if ismember('mean_interval_width', T.Properties.VariableNames); s.mean_interval_width = round(T.mean_interval_width(:).',4); end
    s.note = '90% prediction intervals from quantile regression forests (surrogate uncertainty, not measurement uncertainty).';
end

function s = localShieldStruct(rec)
% Deterministic safety-shield verdict carried in the supervisory recommendation.
    s = struct('available', false);
    if isempty(rec) || ~isfield(rec,'safety_shield'); return; end
    sh = rec.safety_shield;
    s.available = true;
    s.gate_passed   = localBool(sh,'gate_passed', false);
    s.research_only = localBool(sh,'research_only', true);
    if isfield(sh,'basis'); s.basis = localGet(sh,'basis',''); end
    if isfield(sh,'violations'); s.violations = localCellstr(sh.violations); end
    if isfield(sh,'advisories'); s.advisories = localCellstr(sh.advisories); end
    if isfield(sh,'predicted'); s.conservative_bounds = sh.predicted; end
    s.note = 'Mandatory deterministic shield; AI/Gemini cannot bypass it. Uses conservative uncertainty bounds when available.';
end

function s = localRobustStruct(T)
% Reference to the robust (uncertainty-aware) Pareto front.
    s = struct('available', false);
    if isempty(T) || ~ismember('robust_score', T.Properties.VariableNames); return; end
    s.available = true;
    s.n_solutions = height(T);
    if ismember('cleaning_score_lower', T.Properties.VariableNames)
        s.min_cleaning_lower_bound = round(min(T.cleaning_score_lower),3);
    end
    lab = string(T.selection_label); m = strlength(lab)>0;
    s.labelled = cellstr(lab(m));
    s.note = 'Robust front selects on conservative bounds and penalizes high-uncertainty recipes.';
end

function s = localCfStruct(T)
% Counterfactual interventions: deltas vs baseline + best compromise.
    s = struct('available', false);
    if isempty(T) || ~ismember('intervention', T.Properties.VariableNames); return; end
    s.available = true;
    items = {};
    for i = 1:height(T)
        it = struct('intervention', char(string(T.intervention(i))));
        if ismember('applied_delta', T.Properties.VariableNames)
            it.applied_delta = char(string(T.applied_delta(i)));   % realized post-clamp change
        end
        for f = {'cleaning_score','d_cleaning_score','water_L','d_water_L', ...
                 'total_energy_kWh','d_total_energy_kWh','COD_mgL','d_COD_mgL','CO2eq_kg','d_CO2eq_kg'}
            if ismember(f{1}, T.Properties.VariableNames); it.(f{1}) = T.(f{1})(i); end
        end
        if ismember('feasible', T.Properties.VariableNames); it.feasible = logical(T.feasible(i)); end
        items{end+1} = it; %#ok<AGROW>
    end
    s.interventions = items;
    if ismember('is_best_compromise', T.Properties.VariableNames)
        idx = find(logical(T.is_best_compromise),1);
        if ~isempty(idx); s.best_compromise = char(string(T.intervention(idx))); end
    end
end

function s = localHypStruct(doc)
    s = struct('available', false, 'n', 0, 'items', {{}});
    if isempty(doc) || ~isfield(doc,'hypotheses'); return; end
    H = doc.hypotheses; if iscell(H); H = [H{:}]; end
    s.available = true; s.n = numel(H);
    if isfield(doc,'source'); s.source = doc.source; end
    items = {};
    for i = 1:numel(H)
        items{end+1} = struct('id', localGet(H(i),'id',''), ...
            'statement', localGet(H(i),'statement',''), ...
            'expected_direction', localGet(H(i),'expected_direction',''), ...
            'scientific_value', localGet(H(i),'scientific_value','')); %#ok<AGROW>
    end
    s.items = items;
end

function s = localHypValStruct(T)
    s = struct('available', false);
    if isempty(T) || ~ismember('support', T.Properties.VariableNames); return; end
    s.available = true;
    sup = string(T.support);
    s.n_total = height(T);
    s.n_supported = sum(sup=="supported");
    s.n_partially = sum(sup=="partially_supported");
    s.n_not_supported = sum(sup=="not_supported");
    s.n_inconclusive = sum(sup=="inconclusive");
    rows = {};
    for i = 1:height(T)
        rows{end+1} = struct('id', char(string(T.id(i))), ...
            'support', char(sup(i)), ...
            'observed_corr', T.observed_corr(i)); %#ok<AGROW>
    end
    s.rows = rows;
end

function s = localAuditStruct(A)
    s = struct('available', false, 'n_high_severity', 0);
    if isempty(A); return; end
    s.available = true;
    if isfield(A,'n_high_severity'); s.n_high_severity = A.n_high_severity; end
    if isfield(A,'source'); s.source = A.source; end
    flags = {};
    if isfield(A,'model_audit_flags')
        F = A.model_audit_flags; if iscell(F); F = [F{:}]; end
        for i = 1:numel(F)
            flags{end+1} = struct('severity', localGet(F(i),'severity',''), ...
                'model_component', localGet(F(i),'model_component',''), ...
                'issue', localGet(F(i),'issue','')); %#ok<AGROW>
        end
    end
    s.flags = flags;
    if isfield(A,'calibration_priorities'); s.calibration_priorities = localCellstr(A.calibration_priorities); end
end

function s = localPolicyStruct(cfg)
    s = struct('available', false);
    if isempty(cfg); return; end
    s.available = true;
    s.profile = localGet(cfg,'profile','unspecified');
    s.policy_name = localGet(cfg,'policy_name','');
    if isfield(cfg,'constraints'); s.constraints = cfg.constraints; end
    if isfield(cfg,'objective_weights'); s.objective_weights = cfg.objective_weights; end
    if isfield(cfg,'risk_tolerance'); s.risk_tolerance = localGet(cfg,'risk_tolerance',''); end
end

function s = localSupervStruct(rec)
    s = struct('available', false);
    if isempty(rec); return; end
    s.available = true;
    s.research_only = localBool(rec,'research_only', false);
    s.human_approval_required = localBool(rec,'human_approval_required', true);
    s.not_for_real_time_control = localBool(rec,'not_for_real_time_control', true);
    if isfield(rec,'safety_gate') && isfield(rec.safety_gate,'passed')
        s.safety_gate_passed = rec.safety_gate.passed;
        if isfield(rec.safety_gate,'n_passed'); s.n_passed = rec.safety_gate.n_passed; end
        if isfield(rec.safety_gate,'n_candidates'); s.n_candidates = rec.safety_gate.n_candidates; end
        if isfield(rec.safety_gate,'failed_checks'); s.global_failed_checks = localCellstr(rec.safety_gate.failed_checks); end
    end
    if isfield(rec,'selected_recipe'); s.selected_recipe = rec.selected_recipe; end
    if isfield(rec,'manager_summary'); s.manager_summary = localGet(rec,'manager_summary',''); end
    if isfield(rec,'engineer_summary'); s.engineer_summary = localGet(rec,'engineer_summary',''); end
end

function reqs = localRealDataNeeds(A)
    reqs = {'Industrial CIP operating logs for coefficient calibration.'; ...
            'Microbiological / ATP measurements to validate cleaning_score.'; ...
            'Time-resolved effluent COD to fix the COD sub-model.'; ...
            'Certified food-safety / HACCP constraints.'};
    if ~isempty(A) && isfield(A,'minimum_real_measurements_needed')
        extra = localCellstr(A.minimum_real_measurements_needed);
        for i = 1:numel(extra); reqs{end+1} = extra{i}; end %#ok<AGROW>
    end
end

% ======================================================================
function localWriteMarkdown(outMd, d, manifest)
    L = {};
    L{end+1} = '<!-- Author: Ketney Otto';
    L{end+1} = '     Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania';
    L{end+1} = '     Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154 -->';
    L{end+1} = '';
    L{end+1} = '# AI Decision Dossier — Dairy CIP Self-Explaining Digital Twin';
    L{end+1} = '';
    L{end+1} = '> ⚠️ **SIMULATION-GENERATED SYNTHETIC DATA.** Proof-of-concept, uncalibrated.';
    L{end+1} = '> Decision **support** only — not a decision, not validated for plant use.';
    L{end+1} = '';
    L{end+1} = sprintf('- **Run id:** `%s`', d.run_id);
    L{end+1} = sprintf('- **Generated:** %s', d.generated);
    L{end+1} = sprintf('- **Scenarios (dataset rows):** %s', localNum(d.scenario_count));
    L{end+1} = sprintf('- **Data source:** %s', d.data_source);
    L{end+1} = sprintf('- **Generative-AI mode:** %s (model: %s)', d.gemini_mode, d.gemini_model);
    L{end+1} = '';
    L{end+1} = '## Scientific framing';
    L{end+1} = d.framing;
    L{end+1} = '';

    % Surrogate metrics
    L{end+1} = '## 1. Surrogate accuracy (held-out)';
    if d.surrogate_metrics.available
        L{end+1} = '| Target | R² |';
        L{end+1} = '|---|---|';
        for i = 1:numel(d.surrogate_metrics.targets)
            L{end+1} = sprintf('| %s | %.3f |', d.surrogate_metrics.targets{i}, d.surrogate_metrics.R2(i)); %#ok<AGROW>
        end
    else
        L{end+1} = '_surrogate_metrics.csv not available._';
    end
    L{end+1} = '';

    % Hypotheses
    L{end+1} = '## 2. AI-generated hypotheses';
    if d.hypotheses.available
        L{end+1} = sprintf('%d hypotheses proposed (source: %s).', d.hypotheses.n, localFieldOr(d.hypotheses,'source','?'));
        for i = 1:numel(d.hypotheses.items)
            it = d.hypotheses.items{i};
            L{end+1} = sprintf('- **%s** (%s, %s): %s', it.id, it.expected_direction, it.scientific_value, it.statement); %#ok<AGROW>
        end
    else
        L{end+1} = '_ai_hypotheses.json not available._';
    end
    L{end+1} = '';

    % Hypothesis validation
    L{end+1} = '## 3. Deterministic hypothesis validation (MATLAB, no Gemini)';
    if d.hypothesis_validation.available
        v = d.hypothesis_validation;
        L{end+1} = sprintf('supported=%d, partially=%d, not_supported=%d, inconclusive=%d (of %d).', ...
            v.n_supported, v.n_partially, v.n_not_supported, v.n_inconclusive, v.n_total);
        for i = 1:numel(v.rows)
            r = v.rows{i};
            L{end+1} = sprintf('- %s: **%s** (r=%.3f)', r.id, r.support, r.observed_corr); %#ok<AGROW>
        end
    else
        L{end+1} = '_ai_hypothesis_validation.csv not available._';
    end
    L{end+1} = '';

    % Model audit
    L{end+1} = '## 4. Model audit (human review required)';
    if d.model_audit.available
        L{end+1} = sprintf('High-severity flags: **%d** (source: %s). Parameters were NOT modified.', ...
            d.model_audit.n_high_severity, localFieldOr(d.model_audit,'source','?'));
        for i = 1:numel(d.model_audit.flags)
            f = d.model_audit.flags{i};
            L{end+1} = sprintf('- [%s] **%s** — %s', upper(f.severity), f.model_component, f.issue); %#ok<AGROW>
        end
    else
        L{end+1} = '_model_audit_report.json not available._';
    end
    L{end+1} = '';

    % Policy
    L{end+1} = '## 5. Active policy';
    if d.policy.available
        L{end+1} = sprintf('- **Profile:** %s — %s', d.policy.profile, localFieldOr(d.policy,'policy_name',''));
        if isfield(d.policy,'risk_tolerance'); L{end+1} = sprintf('- **Risk tolerance:** %s', d.policy.risk_tolerance); end
        if isfield(d.policy,'constraints')
            L{end+1} = sprintf('- **Min cleaning score:** %s', localNum(localStructGet(d.policy.constraints,'min_cleaning_score')));
        end
    else
        L{end+1} = '_selected_policy_config.json not available._';
    end
    L{end+1} = '';

    % Supervisory recommendation
    L{end+1} = '## 6. Virtual supervisory recommendation';
    if d.supervisory_recommendation.available
        s = d.supervisory_recommendation;
        L{end+1} = sprintf('- **Safety gate passed:** %s', localTF(localFieldOr(s,'safety_gate_passed',false)));
        L{end+1} = sprintf('- **Research-only:** %s', localTF(s.research_only));
        L{end+1} = sprintf('- **Human approval required:** %s', localTF(s.human_approval_required));
        L{end+1} = sprintf('- **Not for real-time control:** %s', localTF(s.not_for_real_time_control));
        if isfield(s,'n_passed') && isfield(s,'n_candidates')
            L{end+1} = sprintf('- **Candidates passing gate:** %d / %d', s.n_passed, s.n_candidates);
        end
        if isfield(s,'manager_summary') && ~isempty(s.manager_summary)
            L{end+1} = ''; L{end+1} = '**Manager summary.** '; L{end+1} = s.manager_summary;
        end
        if isfield(s,'engineer_summary') && ~isempty(s.engineer_summary)
            L{end+1} = ''; L{end+1} = '**Engineer summary.** '; L{end+1} = s.engineer_summary;
        end
        if isfield(s,'global_failed_checks') && ~isempty(s.global_failed_checks)
            L{end+1} = ''; L{end+1} = '**Global gate notes:**';
            for i = 1:numel(s.global_failed_checks); L{end+1} = sprintf('- %s', s.global_failed_checks{i}); end %#ok<AGROW>
        end
    else
        L{end+1} = '_ai_supervisory_recommendation.json not available._';
    end
    L{end+1} = '';

    % Uncertainty
    L{end+1} = '## 6b. Surrogate uncertainty (quantile regression forests)';
    if d.uncertainty.available
        L{end+1} = '| Target | R² | 90% coverage | mean interval width |';
        L{end+1} = '|---|---|---|---|';
        for i = 1:numel(d.uncertainty.targets)
            cov = localIdx(d.uncertainty,'coverage_90',i); wid = localIdx(d.uncertainty,'mean_interval_width',i);
            r2  = localIdx(d.uncertainty,'R2',i);
            L{end+1} = sprintf('| %s | %.3f | %.3f | %.4g |', d.uncertainty.targets{i}, r2, cov, wid); %#ok<AGROW>
        end
        L{end+1} = '_Surrogate uncertainty over the simulator, NOT measurement uncertainty._';
    else
        L{end+1} = '_uncertainty_surrogate_metrics.csv not available._';
    end
    L{end+1} = '';

    % Safety shield
    L{end+1} = '## 6c. Deterministic safety shield';
    if d.safety_shield.available
        sh = d.safety_shield;
        L{end+1} = sprintf('- **Shield gate passed:** %s (basis: %s)', localTF(sh.gate_passed), localFieldOr(sh,'basis','n/a'));
        L{end+1} = sprintf('- **Research-only:** %s', localTF(sh.research_only));
        if isfield(sh,'violations') && ~isempty(sh.violations)
            L{end+1} = '- **Hard violations:**';
            for i = 1:numel(sh.violations); L{end+1} = sprintf('  - %s', sh.violations{i}); end %#ok<AGROW>
        else
            L{end+1} = '- No hard violations on the selected recipe.';
        end
        if isfield(sh,'advisories') && ~isempty(sh.advisories)
            L{end+1} = '- **Research-only advisories (why it is not deployment-ready):**';
            for i = 1:numel(sh.advisories); L{end+1} = sprintf('  - %s', sh.advisories{i}); end %#ok<AGROW>
        else
            L{end+1} = '- No research-only advisories.';
        end
        L{end+1} = '- The shield is MANDATORY: AI/Gemini cannot bypass it; human approval still required.';
    else
        L{end+1} = '_No safety-shield record available._';
    end
    L{end+1} = '';

    % Robust optimization
    L{end+1} = '## 6d. Robust (uncertainty-aware) Pareto';
    if d.robust_optimization.available
        r = d.robust_optimization;
        L{end+1} = sprintf('- Robust front solutions: %d (min cleaning lower-bound on front: %s%%).', ...
            r.n_solutions, localNum(localFieldOr(r,'min_cleaning_lower_bound',NaN)));
        L{end+1} = '- Selection uses CONSERVATIVE bounds (cleaning q05, COD/hygienic q95) and penalizes high uncertainty.';
    else
        L{end+1} = '_robust_pareto_solutions.csv not available._';
    end
    L{end+1} = '';

    % Counterfactual alternatives
    L{end+1} = '## 6e. Counterfactual alternatives';
    if d.counterfactual_alternatives.available
        cf = d.counterfactual_alternatives;
        if isfield(cf,'best_compromise'); L{end+1} = sprintf('**Best compromise intervention:** `%s`.', cf.best_compromise); end
        L{end+1} = '| Intervention | applied (after clamp) | cleaning | dClean | dWater | dEnergy | dCOD | feasible |';
        L{end+1} = '|---|---|---|---|---|---|---|---|';
        for i = 1:numel(cf.interventions)
            it = cf.interventions{i};
            L{end+1} = sprintf('| %s | %s | %.1f | %+.2f | %+.0f | %+.2f | %+.0f | %s |', it.intervention, ...
                localFieldOr(it,'applied_delta','-'), ...
                localFieldOr(it,'cleaning_score',NaN), localFieldOr(it,'d_cleaning_score',NaN), ...
                localFieldOr(it,'d_water_L',NaN), localFieldOr(it,'d_total_energy_kWh',NaN), ...
                localFieldOr(it,'d_COD_mgL',NaN), localTF(localFieldOr(it,'feasible',false))); %#ok<AGROW>
        end
        L{end+1} = '_Labels are the REQUESTED change; "applied (after clamp)" is the realized change after clamping to bounds (e.g. water_rec_+0.15 may clamp to a smaller delta)._';
    else
        L{end+1} = '_counterfactual_cip_results.csv not available._';
    end
    L{end+1} = '';

    % Limitations + real data
    L{end+1} = '## 7. Limitations';
    for i = 1:numel(d.limitations); L{end+1} = sprintf('- %s', d.limitations{i}); end %#ok<AGROW>
    L{end+1} = '';
    L{end+1} = '## 8. Real data required before any operational use';
    for i = 1:numel(d.real_data_needed_before_operational_use)
        L{end+1} = sprintf('- %s', d.real_data_needed_before_operational_use{i}); %#ok<AGROW>
    end
    L{end+1} = '';

    % Consistency
    L{end+1} = '## 9. Run consistency';
    if isfield(manifest,'consistency_warnings') && ~isempty(manifest.consistency_warnings)
        cw = manifest.consistency_warnings; if ~iscell(cw); cw = {cw}; end
        for i = 1:numel(cw); L{end+1} = sprintf('- [!] %s', cw{i}); end %#ok<AGROW>
    else
        L{end+1} = '- No consistency warnings.';
    end
    L{end+1} = '';
    L{end+1} = '---';
    L{end+1} = '_Generated by build_ai_decision_dossier.m. Gemini is decision support, never ground truth; numeric decisions are made by deterministic MATLAB code; human approval is mandatory._';

    txt = strjoin(L, newline);
    fid = fopen(outMd,'w');
    if fid < 0; error('build_ai_decision_dossier:fopenmd','Cannot write %s', outMd); end
    fwrite(fid, txt, 'char'); fclose(fid);
end

% ===== helpers ===========================================================
function T = localReadTable(p)
    T = table();
    if exist(p,'file')==2
        try
            % Explicit comma delimiter: free-text columns (statement/note) contain
            % spaces/commas that can make readtable auto-detect the wrong delimiter.
            T = readtable(p, 'Delimiter',',', 'TextType','string', 'VariableNamingRule','preserve');
        catch
            T = table();
        end
    end
end

function s = localReadJson(p)
    s = [];
    if exist(p,'file')==2
        try
            s = jsondecode(fileread(p));
        catch
            s = [];
        end
    end
end

function v = localGet(s, f, default)
    v = default;
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        try
            v = char(string(s.(f)));
        catch
            v = default;
        end
    end
end

function v = localFieldOr(s, f, default)
    v = default;
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)); v = s.(f); end
end

function v = localIdx(s, f, i)
% i-th element of a numeric field if present, else NaN.
    v = NaN;
    if isstruct(s) && isfield(s,f) && numel(s.(f)) >= i; v = s.(f)(i); end
end

function v = localStructGet(s, f)
    v = NaN;
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)); v = s.(f); end
end

function b = localBool(s, f, default)
    b = default;
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)); b = logical(s.(f)); end
end

function c = localCellstr(x)
    if isempty(x); c = {}; return; end
    if ischar(x); c = {x};
    elseif isstring(x); c = cellstr(x);
    elseif iscell(x); c = cellfun(@(e) char(string(e)), x, 'UniformOutput', false);
    else; c = {};
    end
    c = c(:);
end

function s = localNum(x)
    if isnumeric(x) && isscalar(x) && isfinite(x); s = num2str(x); else; s = char(string(x)); end
end

function s = localTF(b)
    if islogical(b) || isnumeric(b); if b; s = 'yes'; else; s = 'no'; end
    else; s = char(string(b)); end
end

function v = localOpt(opts, field, default)
    if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
        v = opts.(field);
    else
        v = default;
    end
end
