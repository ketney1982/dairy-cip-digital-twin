% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function [hypotheses, out] = gemini_hypothesis_generator()
%GEMINI_HYPOTHESIS_GENERATOR  AI generation of testable scientific hypotheses.
%
%   [HYPOTHESES, OUT] = GEMINI_HYPOTHESIS_GENERATOR() asks Gemini to propose
%   FALSIFIABLE hypotheses about the dairy CIP digital twin, grounded in the
%   compact dataset summary, validation report, surrogate metrics, Pareto
%   solutions and the plausibility audit. The hypotheses are meant to be tested
%   DETERMINISTICALLY by validate_ai_hypotheses.m (no Gemini in the loop there).
%
%   GOVERNANCE:
%   * Gemini PROPOSES hypotheses; it does not confirm them and is not ground truth.
%   * Output is sanitized locally; each hypothesis is given machine-checkable
%     fields (variables_involved as dataset column names, expected_direction).
%   * If GEMINI_API_KEY is missing or the response is invalid, a deterministic
%     MOCK set (>= 6 hypotheses) is produced and clearly labelled.
%   * All artifacts refer to SIMULATION-GENERATED SYNTHETIC DATA.
%
%   Output: results/ai_hypotheses.json
%
%   See also: VALIDATE_AI_HYPOTHESES, GEMINI_EXPERIMENT_DESIGNER, GEMINI_CALL.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    resDir = fullfile(root,'results');
    if ~exist(resDir,'dir'); mkdir(resDir); end
    outPath = fullfile(resDir,'ai_hypotheses.json');

    % ---- Context artifacts (read-or-empty; never hard-fail) -------------
    summaryTxt    = localReadOrEmpty(fullfile(resDir,'dataset_summary.json'));
    validationTxt = localReadOrEmpty(fullfile(resDir,'dataset_validation_report.txt'));
    metricsTxt    = localReadOrEmpty(fullfile(resDir,'surrogate_metrics.csv'));
    paretoTxt     = localReadOrEmpty(fullfile(resDir,'pareto_solutions.csv'));
    auditTxt      = localReadOrEmpty(fullfile(resDir,'plausibility_audit.json'));

    P = cip_parameters();
    colList = [P.var_names, P.targets, {'NaOH_residual_mgL'}];

    sys = strjoin({ ...
        'You are a scientific hypothesis generator for a dairy CIP digital-twin study.', ...
        'You receive ONLY summary statistics, metrics and reports of a SYNTHETIC dataset.', ...
        'Generate FALSIFIABLE, testable hypotheses about input-output relationships.', ...
        'HARD RULES:', ...
        '1. Return VALID JSON ONLY. No markdown, no prose, no code fences.', ...
        '2. Do NOT claim industrial validation; data are simulation-generated.', ...
        '3. variables_involved MUST use EXACT dataset column names from this list:', ...
        ['   ' strjoin(colList, ', ')], ...
        '   List the PRIMARY predictor first and the OUTCOME column last.', ...
        '4. expected_direction MUST be one of: positive | negative | nonmonotonic.', ...
        '   (sign of the relationship between the primary predictor and the outcome).', ...
        '5. test_method MUST be one of: correlation | regression | sensitivity |', ...
        '   pareto_comparison | ai_designed_simulation.', ...
        '6. scientific_value MUST be one of: low | medium | high.', ...
        '7. Provide 6 to 15 hypotheses. Give each a unique id H1, H2, ...', ...
        'Required JSON shape:', ...
        '{"hypotheses":[{"id":"H1","statement":"...","mechanistic_rationale":"...",', ...
        '  "variables_involved":["...","..."],"test_method":"...",', ...
        '  "expected_direction":"positive|negative|nonmonotonic",', ...
        '  "required_artifacts":["..."],"risk_if_false":"...",', ...
        '  "scientific_value":"low|medium|high"}]}'}, newline);

    usr = strjoin({ ...
        'DATASET SUMMARY (JSON):', summaryTxt, '', ...
        'VALIDATION REPORT (text):', validationTxt, '', ...
        'SURROGATE METRICS (CSV):', metricsTxt, '', ...
        'PARETO SOLUTIONS (CSV head):', localHead(paretoTxt, 25), '', ...
        'PLAUSIBILITY AUDIT (JSON):', auditTxt, '', ...
        'Focus on water/energy/COD/CO2/cleaning trade-offs, the soil0->COD link,', ...
        'recovery effects (heat_rec, water_rec), and the EHPI index behaviour.'}, newline);

    [txt, info] = gemini_call(sys, usr, struct('json_only',true,'temperature',0.4,'max_tokens',8192));

    usedMock = false; doc = struct();
    if info.ok
        try
            doc = jsondecode(localStripFences(txt));
        catch ME
            warning('gemini_hypothesis_generator:parse','Bad JSON (%s); using MOCK.', ME.message);
            usedMock = true;
        end
    else
        usedMock = true;
        if ~strcmp(info.status,'mock_mode')   % deliberate mock is not a warning
            warning('gemini_hypothesis_generator:noLLM','Gemini unavailable (%s); using MOCK.', info.status);
        end
    end

    if usedMock
        doc = localMockHypotheses();
    end

    % ---- Sanitize -------------------------------------------------------
    hypotheses = localSanitize(doc, colList);

    out = struct();
    out.hypotheses = hypotheses;
    if usedMock; out.source = 'MOCK_fallback'; else; out.source = 'gemini_live'; end
    out.data_label = 'simulation-generated synthetic data - NOT real industrial data';
    out.governance_note = ['Gemini proposes hypotheses; they are NOT confirmed here. ', ...
        'Deterministic testing is performed by validate_ai_hypotheses.m.'];
    out.n_hypotheses = numel(hypotheses);

    fid = fopen(outPath,'w');
    if fid < 0; error('gemini_hypothesis_generator:fopen','Cannot write %s', outPath); end
    fwrite(fid, jsonencode(out,'PrettyPrint',true), 'char'); fclose(fid);

    tag = gemini_mode_tag(info, usedMock);
    fprintf('[gemini_hypothesis_generator] (%s) %d hypotheses -> %s\n', tag, numel(hypotheses), outPath);
end

% ======================================================================
function H = localSanitize(doc, colList)
% Force a clean struct array with all required fields and valid enum values.
    raw = {};
    if isfield(doc,'hypotheses')
        h = doc.hypotheses;
        if isstruct(h); raw = num2cell(h); elseif iscell(h); raw = h; end
    end
    validTest = {'correlation','regression','sensitivity','pareto_comparison','ai_designed_simulation'};
    validDir  = {'positive','negative','nonmonotonic'};
    validVal  = {'low','medium','high'};

    nRaw = min(20, numel(raw));
    keep = cell(1, nRaw);          % preallocate (no AGROW)
    nk = 0;
    for i = 1:nRaw
        s = raw{i};
        if ~isstruct(s); continue; end
        statement = localStr(s,'statement','');
        if isempty(statement); continue; end             % a hypothesis needs a statement
        nk = nk + 1;
        h = struct();
        h.id = sprintf('H%d', nk);                       % sequential, stable id
        h.statement = statement;
        h.mechanistic_rationale = localStr(s,'mechanistic_rationale','');
        h.variables_involved = localCleanVars(localCellstr(s,'variables_involved'), colList);
        h.test_method = localEnum(localStr(s,'test_method','correlation'), validTest, 'correlation');
        h.expected_direction = localEnum(lower(localStr(s,'expected_direction','nonmonotonic')), validDir, 'nonmonotonic');
        h.required_artifacts = localCellstr(s,'required_artifacts');
        if isempty(h.required_artifacts)
            h.required_artifacts = {'data/dairy_cip_synthetic_dataset.csv'};
        end
        h.risk_if_false = localStr(s,'risk_if_false','');
        h.scientific_value = localEnum(lower(localStr(s,'scientific_value','medium')), validVal, 'medium');
        keep{nk} = h;
    end
    keep = keep(1:nk);
    if isempty(keep)
        H = localSanitize(localMockHypotheses(), colList);   % never return empty
        return;
    end
    H = [keep{:}];
end

% ======================================================================
function doc = localMockHypotheses()
% Deterministic, machine-checkable hypotheses covering the required themes.
    mk = @(id,st,rat,vars,tm,dir,art,risk,val) struct( ...
        'id',id,'statement',st,'mechanistic_rationale',rat, ...
        'variables_involved',{vars},'test_method',tm,'expected_direction',dir, ...
        'required_artifacts',{art},'risk_if_false',risk,'scientific_value',val);
    DS = {'data/dairy_cip_synthetic_dataset.csv'};

    h = {};
    h{end+1} = mk('H1', ...
        'Higher water recovery reduces per-cycle water consumption.', ...
        'water_L integrates flow scaled by (1 - water_rec), so increasing water_rec must lower water_L.', ...
        {'water_rec','water_L'}, 'correlation','negative', DS, ...
        'If false, the water-recovery term in the water model is mis-wired.','high');
    h{end+1} = mk('H2', ...
        'Reducing fresh water (higher water_rec) concentrates the effluent, raising COD_mgL.', ...
        'Less dilution should increase effluent concentration if COD tracked discharged mass per litre.', ...
        {'water_rec','COD_mgL'}, 'regression','positive', DS, ...
        'If false, COD is modelled as a time-average decoupled from water volume (a known simplification).','high');
    h{end+1} = mk('H3', ...
        'Heat recovery reduces total energy use.', ...
        'Thermal power is scaled by (1 - heat_rec); higher heat_rec lowers thermal_energy and thus total_energy_kWh.', ...
        {'heat_rec','total_energy_kWh'}, 'correlation','negative', DS, ...
        'If false, the heat-recovery factor is not applied to the thermal model.','high');
    h{end+1} = mk('H4', ...
        'Heat recovery reduces CO2-equivalent emissions.', ...
        'CO2eq is dominated by thermal energy * EF_thermal, which falls with heat_rec.', ...
        {'heat_rec','CO2eq_kg'}, 'correlation','negative', DS, ...
        'If false, emissions are decoupled from thermal energy.','medium');
    h{end+1} = mk('H5', ...
        'Longer alkaline-wash duration increases cleaning score.', ...
        'First-order soil removal over a longer t_alk removes more soil, raising cleaning_score = (1-soil)*100.', ...
        {'t_alk','cleaning_score'}, 'correlation','positive', DS, ...
        'If false, the alkaline phase contributes little to soil removal.','high');
    h{end+1} = mk('H6', ...
        'Higher wash temperature increases cleaning score.', ...
        'The alkaline rate constant scales with exp(alpha_T*(T_C - T_ref)); higher T_C speeds soil removal.', ...
        {'T_C','cleaning_score'}, 'correlation','positive', DS, ...
        'If false, the Arrhenius-like temperature term is ineffective.','medium');
    h{end+1} = mk('H7', ...
        'Higher NaOH concentration increases cleaning score.', ...
        'The alkaline rate scales with (NaOH_pct/NaOH_ref)^gamma_NaOH; more NaOH speeds soil removal.', ...
        {'NaOH_pct','cleaning_score'}, 'correlation','positive', DS, ...
        'If false, chemical concentration does not aid cleaning in the model.','medium');
    h{end+1} = mk('H8', ...
        'Higher initial soil load decreases cleaning score.', ...
        'With finite kinetics, a larger soil0 leaves more residual soil at cycle end, lowering cleaning_score.', ...
        {'soil0','cleaning_score'}, 'correlation','negative', DS, ...
        'If false, the model is insensitive to the soiling uncertainty condition.','high');
    h{end+1} = mk('H9', ...
        'Higher initial soil load should increase effluent COD.', ...
        'More organic soil removed should raise organic COD; a near-zero soil0-COD link signals a model gap.', ...
        {'soil0','COD_mgL'}, 'regression','positive', DS, ...
        'If false (corr ~ 0), COD does not track organic soil - a HIGH-priority calibration issue.','high');
    h{end+1} = mk('H10', ...
        'Higher temperature increases total energy use.', ...
        'Thermal power ~ m_dot*cp*(T_C - T_in); higher T_C raises thermal energy and total_energy_kWh.', ...
        {'T_C','total_energy_kWh'}, 'correlation','positive', DS, ...
        'If false, the thermal energy model is insensitive to setpoint temperature.','medium');
    h{end+1} = mk('H11', ...
        'EHPI rewards low-burden recipes: it rises as water use falls.', ...
        'EHPI = 100*cleaning_norm/(1+penalty_env); lower water_L lowers the penalty, raising EHPI - so balanced, low-burden recipes (not cleaning extremes) score best.', ...
        {'water_L','EHPI'}, 'correlation','negative', DS, ...
        'If false, the EHPI normalization/penalty weighting needs revision.','medium');

    doc = struct('hypotheses', [h{:}]);
end

% ======================================================================
function v = localCleanVars(vars, colList)
% Keep only recognized dataset column names, preserving order.
    v = {};
    for i = 1:numel(vars)
        nm = strtrim(char(vars{i}));
        if any(strcmp(colList, nm)); v{end+1} = nm; end %#ok<AGROW>
    end
end

function s = localStr(st, f, default)
    s = default;
    if isstruct(st) && isfield(st,f) && ~isempty(st.(f))
        try
            s = char(string(st.(f)));
        catch
            s = default;
        end
    end
end

function c = localCellstr(st, f)
    c = {};
    if isstruct(st) && isfield(st,f) && ~isempty(st.(f))
        x = st.(f);
        if ischar(x); c = {x};
        elseif isstring(x); c = cellstr(x);
        elseif iscell(x); c = cellfun(@(e) char(string(e)), x, 'UniformOutput', false);
        end
    end
end

function e = localEnum(val, allowed, default)
    e = default;
    if any(strcmp(allowed, val)); e = val; end
end

function txt = localReadOrEmpty(fpath)
    if exist(fpath,'file') == 2
        try
            txt = fileread(fpath);
        catch
            txt = '';
        end
    else
        txt = '';
    end
end

function h = localHead(txt, n)
% First n lines of a (possibly large) text block, to keep prompts bounded.
    if isempty(txt); h = ''; return; end
    lines = splitlines(string(txt));
    h = char(strjoin(lines(1:min(n,numel(lines))), newline));
end

function s = localStripFences(s)
    s = char(s);
    s = regexprep(s,'^\s*```[a-zA-Z]*\s*','');
    s = regexprep(s,'\s*```\s*$','');
end
