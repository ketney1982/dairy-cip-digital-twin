% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function report = gemini_explain_pareto()
%GEMINI_EXPLAIN_PARETO  Management-oriented explanation of Pareto solutions.
%
%   report = GEMINI_EXPLAIN_PARETO() runs ONLY AFTER numerical optimization is
%   complete. It selects representative Pareto scenarios, sends their numeric
%   metrics to Gemini, and asks for a concise management explanation of the
%   trade-offs. The text is saved to results/gemini_decision_report.txt.
%
%   GOVERNANCE: Gemini explains numbers that were computed by the optimizer; it
%   does NOT generate process data, does NOT claim industrial validation, and
%   does NOT set process values. Any scenario with cleaning_score < 95 is
%   flagged as unacceptable. If GEMINI_API_KEY is missing, a deterministic MOCK
%   report is generated from the same numbers.
%
%   See also: OPTIMIZE_CIP_PARETO, GEMINI_CALL.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    resDir = fullfile(root,'results');
    if ~exist(resDir,'dir'); mkdir(resDir); end
    parPath = fullfile(resDir,'pareto_solutions.csv');
    csvPath = fullfile(root,'data','dairy_cip_synthetic_dataset.csv');
    outPath = fullfile(resDir,'gemini_decision_report.txt');

    if exist(parPath,'file') ~= 2
        error('gemini_explain_pareto:noPareto','Pareto file not found:\n  %s\nRun optimize_cip_pareto first.', parPath);
    end
    Pa = readtable(parPath);

    % ---- Baseline = mean of successful dataset rows ----------------------
    baseline = struct('water_L',NaN,'total_energy_kWh',NaN,'COD_mgL',NaN, ...
                      'CO2eq_kg',NaN,'cleaning_score',NaN,'EHPI',NaN);
    if exist(csvPath,'file')==2
        D = readtable(csvPath);
        D = D(string(D.simulation_status)=="success",:);
        for fn = fieldnames(baseline).'
            if ismember(fn{1}, D.Properties.VariableNames)
                baseline.(fn{1}) = round(mean(D.(fn{1}),'omitnan'),3);
            end
        end
    end

    % ---- Select representative scenarios ---------------------------------
    sel = struct();
    sel.lowest_water    = localPick(Pa,'water_L','min');
    sel.lowest_energy   = localPick(Pa,'total_energy_kWh','min');
    sel.lowest_COD      = localPick(Pa,'COD_mgL','min');
    sel.best_balanced   = localPick(Pa,'EHPI','max');
    sel.highest_cleaning= localPick(Pa,'cleaning_score','max');

    payload = struct('baseline',baseline,'scenarios',sel, ...
        'note','All values are surrogate predictions over SYNTHETIC simulation data.');
    payloadTxt = jsonencode(payload,'PrettyPrint',true);

    % ---- Gemini prompt ---------------------------------------------------
    sys = strjoin({ ...
        'You are an environmental decision-support assistant for a dairy plant.', ...
        'You receive numeric metrics of optimized CIP scenarios (already computed', ...
        'by a multi-objective optimizer over a simulation surrogate).', ...
        'RULES:', ...
        '1. Use ONLY the numbers provided; do not invent process data.', ...
        '2. Do NOT claim real industrial validation; data are synthetic.', ...
        '3. Explain trade-offs among water, energy, COD, CO2eq and cleaning_score.', ...
        '4. Flag ANY scenario with cleaning_score < 95 as UNACCEPTABLE.', ...
        '5. RESEARCH-ONLY proof of concept on SYNTHETIC data. Do NOT issue', ...
        '   operational instructions. NEVER write "implement immediately",', ...
        '   "deploy", "apply now", "go live", or direct setpoint commands', ...
        '   (e.g. "set the temperature to ..."). Frame every suggestion as', ...
        '   research-only and requiring qualified human review and food-safety', ...
        '   sign-off before any use.', ...
        '6. Provide these sections, clearly headed:', ...
        '   - BEST BALANCED SCENARIO', ...
        '   - LOWEST-WATER SCENARIO', ...
        '   - LOWEST-ENERGY SCENARIO', ...
        '   - ENVIRONMENTAL RISK WARNING', ...
        '   - RESEARCH-ONLY CONSIDERATIONS FOR MANAGERS (human review required; concise)'}, newline);
    usr = strjoin({'SCENARIO METRICS (JSON):', payloadTxt}, newline);

    % Budget must cover the model's internal thinking tokens plus the visible
    % report (thinking-capable models, e.g. gemini-3.6-flash). 8192 is ample.
    [txt, info] = gemini_call(sys, usr, struct('json_only',false,'temperature',0.3,'max_tokens',8192));

    usedMock = ~info.ok || isempty(strtrim(char(txt)));
    if usedMock
        if ~strcmp(info.status,'mock_mode')   % deliberate mock is not a warning
            warning('gemini_explain_pareto:noLLM','Gemini unavailable (%s); using MOCK report.', info.status);
        end
        reportText = localMockReport(baseline, sel);
    else
        reportText = char(txt);
    end
    % Governance: neutralize any operational directives and enforce research-only
    % framing before the report is written (defense-in-depth with the prompt; runs
    % on both live and mock text so the artifact is uniformly safe).
    [reportText, sanHits] = gemini_sanitize_report(reportText, true);
    if ~isempty(sanHits)
        fprintf('[gemini_explain_pareto] sanitizer neutralized directive(s): %s\n', strjoin(sanHits, ', '));
    end

    header = sprintf(['DAIRY CIP - GENERATIVE-AI DECISION REPORT%s\n', ...
        'Generated from SIMULATION-GENERATED SYNTHETIC DATA (surrogate predictions).\n', ...
        'Gemini explains numbers; it does not validate the physical model.\n', ...
        '================================================================\n\n'], ...
        ternary(usedMock,'  [MOCK - GEMINI_API_KEY not configured]',''));

    fid = fopen(outPath,'w');
    if fid < 0; error('gemini_explain_pareto:fopen','Cannot write %s', outPath); end
    fwrite(fid, [header reportText], 'char'); fclose(fid);

    tag = gemini_mode_tag(info, usedMock);
    fprintf('[gemini_explain_pareto] (%s) report -> %s\n', tag, outPath);

    report = struct('selected',sel,'baseline',baseline,'text',reportText,'mock',usedMock);
end

% ======================================================================
function s = localPick(T, var, mode)
% Return a struct of the row optimizing var (min/max); guards missing column.
    s = struct();
    if ~ismember(var, T.Properties.VariableNames) || isempty(T); return; end
    x = T.(var);
    if strcmp(mode,'min'); [~,idx] = min(x); else; [~,idx] = max(x); end
    row = T(idx,:);
    fns = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final','NaOH_pct','soil0', ...
           'heat_rec','water_rec','water_L','total_energy_kWh','COD_mgL', ...
           'CO2eq_kg','cleaning_score','EHPI'};
    for f = fns
        if ismember(f{1}, row.Properties.VariableNames)
            s.(f{1}) = round(row.(f{1}),3);
        end
    end
end

% ======================================================================
function txt = localMockReport(baseline, sel)
    nl = newline;
    fmt = @(s) sprintf(['  water=%.1f L, energy=%.2f kWh, COD=%.0f mg/L, ', ...
        'CO2eq=%.2f kg, cleaning=%.1f%%, EHPI=%.1f'], ...
        gv(s,'water_L'), gv(s,'total_energy_kWh'), gv(s,'COD_mgL'), ...
        gv(s,'CO2eq_kg'), gv(s,'cleaning_score'), gv(s,'EHPI'));
    fieldsToCheck = {'lowest_water','lowest_energy','lowest_COD','best_balanced','highest_cleaning'};
    warnParts = cell(1, numel(fieldsToCheck));
    nw = 0;
    for c = fieldsToCheck
        s = sel.(c{1});
        if isfield(s,'cleaning_score') && s.cleaning_score < 95
            nw = nw + 1;
            warnParts{nw} = sprintf('  [!] %s has cleaning_score=%.1f%% (<95) - UNACCEPTABLE.', ...
                c{1}, s.cleaning_score);
        end
    end
    if nw == 0
        warnLines = ['  All listed scenarios meet the 95% cleaning floor.' nl];
    else
        warnLines = [strjoin(warnParts(1:nw), nl) nl];
    end
    txt = strjoin({ ...
        'BEST BALANCED SCENARIO', fmt(sel.best_balanced), ...
        '  Recommended when no single burden dominates; maximizes the EHPI index.', '', ...
        'LOWEST-WATER SCENARIO', fmt(sel.lowest_water), ...
        '  Choose under water-scarcity policies; verify energy/COD remain acceptable.', '', ...
        'LOWEST-ENERGY SCENARIO', fmt(sel.lowest_energy), ...
        '  Choose under carbon/energy-cost pressure; check water use does not rise sharply.', '', ...
        sprintf('BASELINE (dataset mean): water=%.1f L, energy=%.2f kWh, COD=%.0f mg/L, CO2eq=%.2f kg, cleaning=%.1f%%', ...
            gv(baseline,'water_L'), gv(baseline,'total_energy_kWh'), gv(baseline,'COD_mgL'), ...
            gv(baseline,'CO2eq_kg'), gv(baseline,'cleaning_score')), '', ...
        'ENVIRONMENTAL RISK WARNING', warnLines, ...
        'RECOMMENDATION FOR DAIRY MANAGERS', ...
        '  Use the balanced scenario as default; switch to the lowest-water or', ...
        '  lowest-energy recipe when a specific policy dominates. Always keep', ...
        '  cleaning_score at or above 95%. These are SYNTHETIC proof-of-concept', ...
        '  results; validate against plant data and food-safety checks before use.'}, nl);
end

function v = gv(s, f)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)); v = s.(f); else; v = NaN; end
end

function out = ternary(c,a,b)
    if c; out = a; else; out = b; end
end
