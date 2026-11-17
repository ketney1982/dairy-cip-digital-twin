% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function [scenarios, design] = gemini_experiment_designer()
%GEMINI_EXPERIMENT_DESIGNER  AI-assisted design of CIP simulation experiments.
%
%   [SCENARIOS, DESIGN] = GEMINI_EXPERIMENT_DESIGNER() sends context to Gemini
%   and asks it to propose a batch of candidate scenarios for the Simulink
%   digital twin. All proposed values are deterministically clamped to
%   P.lb/P.ub. No Gemini output is used directly as a setpoint.
%
%   GOVERNANCE:
%   * Gemini proposes; MATLAB validates and clamps all values.
%   * No more than 100 scenarios per batch.
%   * If GEMINI_API_KEY missing or response invalid, deterministic MOCK used.
%   * All outputs labelled simulation-generated synthetic data.
%
%   Outputs:
%     results/ai_designed_scenarios.csv
%     results/ai_experiment_design.json
%
%   See also: RUN_AI_DESIGNED_SCENARIOS, CIP_PARAMETERS.

    here  = fileparts(mfilename('fullpath'));
    root  = fileparts(here);
    addpath(here);
    resDir = fullfile(root,'results');
    if ~exist(resDir,'dir'); mkdir(resDir); end

    P = cip_parameters();

    % ---- Load context artifacts ---------------------------------------------
    sumPath   = fullfile(resDir,'dataset_summary.json');
    metPath   = fullfile(resDir,'surrogate_metrics.csv');
    audPath   = fullfile(resDir,'plausibility_audit.json');

    summaryTxt = localReadOrEmpty(sumPath);
    metricsTxt = localReadOrEmpty(metPath);
    auditTxt   = localReadOrEmpty(audPath);

    rangesStruct = struct();
    for k = 1:numel(P.var_names)
        rangesStruct.(P.var_names{k}) = struct('lb', P.lb(k), 'ub', P.ub(k));
    end
    rangesTxt = jsonencode(rangesStruct, 'PrettyPrint', true);

    % ---- Prompt -------------------------------------------------------------
    sys = strjoin({
        'You are a dairy CIP simulation experiment designer for a digital twin study.'
        'You must propose candidate CIP scenarios for a Simulink mechanistic model.'
        'HARD RULES:'
        '1. Return VALID JSON ONLY. No markdown, no prose, no code fences.'
        '2. All numeric values must be within the provided lb/ub ranges.'
        '3. Propose 10-30 scenarios; never exceed 100.'
        '4. Each scenario must have a "purpose" field from:'
        '   boundary | tradeoff | uncertainty | stress_test | hypothesis_test'
        '5. Each scenario must have "hypothesis_link" and "expected_effect" fields.'
        '6. Do NOT recommend real plant setpoints; these are simulation experiments only.'
        '7. Use the surrogate_metrics and dataset_summary to target underexplored regions.'
        '8. JSON shape:'
        '{"experiment_batch_name":"...",'
        ' "rationale":"...",'
        ' "candidate_scenarios":['
        '   {"T_C":...,"Q_m3h":...,"t_pre":...,"t_alk":...,"t_int":...,"t_final":...,'
        '    "NaOH_pct":...,"soil0":...,"heat_rec":...,"water_rec":...,'
        '    "purpose":"...","hypothesis_link":"...","expected_effect":"..."}'
        ' ],'
        ' "coverage_strategy":"...",'
        ' "safety_notes":["..."]}'
    }, newline);

    usr = strjoin({
        'VARIABLE RANGES (JSON):'
        rangesTxt
        ''
        'DATASET SUMMARY:'
        summaryTxt
        ''
        'SURROGATE METRICS:'
        metricsTxt
        ''
        'PLAUSIBILITY AUDIT:'
        auditTxt
        ''
        'SCIENTIFIC OBJECTIVE: Design experiments that probe model uncertainty,'
        'identify Pareto tradeoff boundaries, and test key hypotheses about'
        'water/energy/COD tradeoffs in dairy CIP.'
    }, newline);

    [txt, info] = gemini_call(sys, usr, struct('json_only',true,'temperature',0.3,'max_tokens',8192));

    usedMock = false; design = struct();
    if info.ok
        try
            design = jsondecode(localStripFences(txt));
        catch ME
            warning('gemini_experiment_designer:parse', 'Bad JSON (%s); using MOCK.', ME.message);
            usedMock = true;
        end
    else
        usedMock = true;
        if ~strcmp(info.status,'mock_mode')   % deliberate mock is not a warning
            warning('gemini_experiment_designer:noLLM', 'Gemini unavailable (%s); using MOCK.', info.status);
        end
    end

    if usedMock
        design = localMockDesign(P);
    end

    % ---- Validate and clamp all scenarios -----------------------------------
    design = localValidateDesign(design, P);

    % ---- Extract scenario table ---------------------------------------------
    scenarios = localDesignToTable(design, P);

    % ---- Save artifacts -----------------------------------------------------
    outJson = fullfile(resDir,'ai_experiment_design.json');
    outCsv  = fullfile(resDir,'ai_designed_scenarios.csv');

    design.data_label = 'simulation-generated synthetic data - NOT real industrial data';
    design.governance_note = 'All values clamped by MATLAB to P.lb/P.ub. Human approval required before operational use.';
    if isfield(design,'rationale')   % scrub directives from free-text rationale
        design.rationale = gemini_sanitize_report(char(design.rationale), false);
    end
    if usedMock
        design.source = 'MOCK_fallback';
    else
        design.source = 'gemini_live';
    end

    fid = fopen(outJson,'w');
    if fid < 0; error('gemini_experiment_designer:fopen','Cannot write %s', outJson); end
    fwrite(fid, jsonencode(design,'PrettyPrint',true), 'char'); fclose(fid);

    if ~isempty(scenarios)
        writetable(scenarios, outCsv);
    end

    tag = gemini_mode_tag(info, usedMock);
    fprintf('[gemini_experiment_designer] (%s) %d scenarios -> %s\n', ...
        tag, height(scenarios), outCsv);
end

% ======================================================================
function design = localValidateDesign(design, P)
% Clamp values, remove invalid rows, enforce batch size limit.
    if ~isfield(design,'experiment_batch_name')
        design.experiment_batch_name = 'batch_validated';
    end
    if ~isfield(design,'rationale'); design.rationale = ''; end
    if ~isfield(design,'coverage_strategy'); design.coverage_strategy = ''; end
    if ~isfield(design,'safety_notes'); design.safety_notes = {}; end
    if ~isfield(design,'candidate_scenarios')
        design.candidate_scenarios = {};
        return;
    end

    scens = design.candidate_scenarios;
    if isstruct(scens); scens = num2cell(scens); end

    validScens = {};
    vn = P.var_names;
    for i = 1:min(100, numel(scens))
        s = scens{i};
        if ~isstruct(s); continue; end
        valid = true;
        for k = 1:numel(vn)
            fname = vn{k};
            if isfield(s, fname)
                v = s.(fname);
                if ~isnumeric(v) || ~isfinite(v)
                    valid = false; break;
                end
                s.(fname) = min(P.ub(k), max(P.lb(k), v));
            else
                s.(fname) = (P.lb(k) + P.ub(k)) / 2;
            end
        end
        if ~valid; continue; end
        if ~isfield(s,'purpose'); s.purpose = 'tradeoff'; end
        if ~isfield(s,'hypothesis_link'); s.hypothesis_link = ''; end
        if ~isfield(s,'expected_effect'); s.expected_effect = ''; end

        validPurposes = {'boundary','tradeoff','uncertainty','stress_test','hypothesis_test'};
        if ~ismember(char(s.purpose), validPurposes)
            s.purpose = 'tradeoff';
        end
        validScens{end+1} = s; %#ok<AGROW>
    end
    design.candidate_scenarios = validScens;
end

% ======================================================================
function T = localDesignToTable(design, P)
% Convert validated design struct to a MATLAB table.
    scens = design.candidate_scenarios;
    if isempty(scens)
        colNames = [P.var_names, {'purpose','hypothesis_link','expected_effect'}];
        T = array2table(zeros(0, numel(colNames)), 'VariableNames', colNames);
        return;
    end
    if isstruct(scens); scens = num2cell(scens); end
    n = numel(scens);
    vn = P.var_names;
    data = zeros(n, numel(vn));
    purpose       = strings(n,1);
    hyp_link      = strings(n,1);
    exp_effect    = strings(n,1);
    for i = 1:n
        s = scens{i};
        for k = 1:numel(vn)
            if isfield(s, vn{k}); data(i,k) = s.(vn{k}); end
        end
        if isfield(s,'purpose');         purpose(i)    = string(s.purpose); end
        if isfield(s,'hypothesis_link'); hyp_link(i)   = string(s.hypothesis_link); end
        if isfield(s,'expected_effect'); exp_effect(i) = string(s.expected_effect); end
    end
    T = array2table(data, 'VariableNames', vn);
    T.purpose       = cellstr(purpose);
    T.hypothesis_link = cellstr(hyp_link);
    T.expected_effect = cellstr(exp_effect);
end

% ======================================================================
function design = localMockDesign(~)
% Deterministic fallback with 5 archetypal scenario groups.
    design = struct();
    design.experiment_batch_name = 'MOCK_archetypal_batch';
    design.rationale = ['[MOCK] Deterministic fallback scenarios covering boundary cases, ', ...
        'water/COD tradeoffs, energy/hygiene tradeoffs, and soil0 sensitivity.'];
    design.coverage_strategy = 'Five scenario groups targeting distinct regions of the decision space.';
    design.safety_notes = {'All scenarios clamped to P.lb/P.ub'; 'Simulation only - not for plant use'};

    scens = {};

    % Group 1: low water / high COD risk
    s = struct('T_C',55,'Q_m3h',2.8,'t_pre',180,'t_alk',400,'t_int',150, ...
        't_final',200,'NaOH_pct',0.6,'soil0',0.9,'heat_rec',0.0,'water_rec',0.55, ...
        'purpose','stress_test','hypothesis_link','H_water_COD', ...
        'expected_effect','Low water volume but potentially high COD concentration');
    scens{end+1} = s;

    % Group 2: high hygiene / high energy
    s = struct('T_C',80,'Q_m3h',1.0,'t_pre',500,'t_alk',1600,'t_int',500, ...
        't_final',800,'NaOH_pct',2.2,'soil0',0.5,'heat_rec',0.1,'water_rec',0.1, ...
        'purpose','boundary','hypothesis_link','H_hygiene_energy', ...
        'expected_effect','High cleaning_score but high energy and water use');
    scens{end+1} = s;

    % Group 3: low energy / moderate cleaning
    s = struct('T_C',48,'Q_m3h',0.6,'t_pre',150,'t_alk',350,'t_int',130, ...
        't_final',200,'NaOH_pct',0.6,'soil0',0.3,'heat_rec',0.65,'water_rec',0.55, ...
        'purpose','tradeoff','hypothesis_link','H_energy_cleaning', ...
        'expected_effect','Low energy due to heat recovery, moderate cleaning');
    scens{end+1} = s;

    % Group 4: boundary near cleaning_score 95
    s = struct('T_C',50,'Q_m3h',0.7,'t_pre',130,'t_alk',320,'t_int',125, ...
        't_final',185,'NaOH_pct',0.55,'soil0',0.8,'heat_rec',0.3,'water_rec',0.3, ...
        'purpose','boundary','hypothesis_link','H_cleaning_floor', ...
        'expected_effect','Near-minimum cleaning scenario - tests floor constraint');
    scens{end+1} = s;

    % Group 5: high soil0 vs COD relationship test
    s = struct('T_C',65,'Q_m3h',1.5,'t_pre',300,'t_alk',900,'t_int',300, ...
        't_final',400,'NaOH_pct',1.5,'soil0',0.95,'heat_rec',0.3,'water_rec',0.2, ...
        'purpose','hypothesis_test','hypothesis_link','H_soil_COD', ...
        'expected_effect','High soil0 should increase COD discharge');
    scens{end+1} = s;

    % Group 6: minimal soil0 baseline
    s = struct('T_C',65,'Q_m3h',1.5,'t_pre',300,'t_alk',900,'t_int',300, ...
        't_final',400,'NaOH_pct',1.5,'soil0',0.12,'heat_rec',0.3,'water_rec',0.2, ...
        'purpose','hypothesis_test','hypothesis_link','H_soil_COD', ...
        'expected_effect','Low soil0 baseline for soil/COD comparison');
    scens{end+1} = s;

    design.candidate_scenarios = scens;
end

% ======================================================================
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

% ======================================================================
function s = localStripFences(s)
    s = char(s);
    s = regexprep(s,'^\s*```[a-zA-Z]*\s*','');
    s = regexprep(s,'\s*```\s*$','');
end
