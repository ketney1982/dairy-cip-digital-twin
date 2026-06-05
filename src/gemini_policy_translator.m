% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function config = gemini_policy_translator(policy_text, opts)
%GEMINI_POLICY_TRANSLATOR  Translate a policy / profile into optimization config.
%
%   config = GEMINI_POLICY_TRANSLATOR(policy_text) uses the Gemini API to
%   translate a natural-language environmental / regulatory / economic policy
%   into a STRICT JSON optimization configuration (constraints + objective
%   weights + an operational profile) and writes it to
%   results/selected_policy_config.json.
%
%   config = GEMINI_POLICY_TRANSLATOR(policy_text, opts) accepts options:
%       opts.profile   - force one of the canonical operational profiles
%                        (balanced_default | water_scarcity | energy_price_spike
%                        | cod_discharge_limit | carbon_reduction |
%                        hygiene_priority). When set, the matching profile from
%                        cip_policy_profiles is used as the deterministic base
%                        and its policy_text seeds the request.
%       opts.out_path  - explicit output path (default selected_policy_config.json).
%                        Lets run_policy_portfolio write per-profile files without
%                        clobbering the canonical config.
%       opts.force_mock- true to skip the network entirely (deterministic).
%
%   OUTPUT SCHEMA (governed):
%     {"policy_name","profile",
%      "constraints":{"min_cleaning_score","max_COD_mgL","max_hygienic_risk",
%                     "max_water_L","max_total_energy_kWh","max_CO2eq_kg"},
%      "objective_weights":{water_L,total_energy_kWh,COD_mgL,CO2eq_kg,
%                           cleaning_score},
%      "risk_tolerance","human_approval_required","explanation"}
%   objective_weights has EXACTLY FIVE keys and sums to 1. hygienic_risk is
%   deliberately NOT a weight: in the feasible region (cleaning_score >= 95) it is
%   collinear with cleaning_score, so it would double-count it. hygienic_risk is
%   enforced ONLY as the hard constraint max_hygienic_risk.
%   Unconstrained limits are emitted as JSON null (never []), via NaN internally.
%
%   GOVERNANCE: Gemini here ONLY maps policy language to optimization
%   constraints and objective weights. It NEVER proposes process setpoints
%   (temperature, flow, NaOH concentration, CIP time) and is never used inside
%   Simulink or the optimizer. If GEMINI_API_KEY is not configured (or the call
%   fails), a clearly-labelled deterministic MOCK configuration is produced so
%   the pipeline runs end-to-end without a network dependency. human_approval is
%   always required. All numbers refer to SIMULATION-GENERATED SYNTHETIC DATA.
%
%   See also: CIP_POLICY_PROFILES, GEMINI_CALL, OPTIMIZE_CIP_PARETO,
%             RUN_POLICY_PORTFOLIO.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    resDir = fullfile(root,'results');
    if ~exist(resDir,'dir'); mkdir(resDir); end

    if nargin < 2 || isempty(opts); opts = struct(); end
    outPath = fullfile(resDir,'selected_policy_config.json');
    if isfield(opts,'out_path') && ~isempty(opts.out_path); outPath = opts.out_path; end
    forceMock = isfield(opts,'force_mock') && opts.force_mock;

    % ---- Resolve the operational profile (explicit, or auto-detected) ----
    profileName = '';
    if isfield(opts,'profile') && ~isempty(opts.profile)
        profileName = char(opts.profile);
    end
    if (nargin < 1 || isempty(policy_text))
        if isempty(profileName); profileName = 'balanced_default'; end
        prof = cip_policy_profiles(profileName);
        policy_text = prof.policy_text;
    elseif isempty(profileName)
        profileName = localDetectProfile(policy_text);
    end
    base = cip_policy_profiles(profileName);   % deterministic base for this profile

    % ---- Strict system instruction --------------------------------------
    sys = strjoin({ ...
        'You are an environmental optimization policy translator for a dairy', ...
        'Cleaning-in-Place (CIP) decision-support system.', ...
        'Translate the user policy into a STRICT JSON optimization config.', ...
        'HARD RULES:', ...
        '1. Return VALID JSON ONLY. No markdown, no prose, no code fences.', ...
        '2. Do NOT produce process setpoints. Never recommend temperature,', ...
        '   flow rate, NaOH concentration, or CIP phase times.', ...
        '3. Output ONLY constraints, objective weights and metadata.', ...
        '4. objective_weights MUST sum to exactly 1.0 and cover all five keys.', ...
        '5. min_cleaning_score MUST NEVER be below 95.', ...
        '6. For any limit that does NOT apply use JSON null (never [] or 0).', ...
        '7. "profile" MUST equal the provided profile key.', ...
        '8. "human_approval_required" MUST be true.', ...
        sprintf('The operational profile for this request is: "%s".', profileName), ...
        'Required JSON shape:', ...
        '{"policy_name":"...","profile":"<profile_key>",', ...
        ' "constraints":{"min_cleaning_score":<num>=95>,"max_COD_mgL":<num|null>,', ...
        '   "max_hygienic_risk":<0..1|null>,"max_water_L":<num|null>,', ...
        '   "max_total_energy_kWh":<num|null>,"max_CO2eq_kg":<num|null>},', ...
        ' "objective_weights":{"water_L":<>,"total_energy_kWh":<>,"COD_mgL":<>,', ...
        '   "CO2eq_kg":<>,"cleaning_score":<>},', ...
        ' "risk_tolerance":"low|medium|high","human_approval_required":true,', ...
        ' "explanation":"..."}'}, newline);

    usr = strjoin({ ...
        sprintf('PROFILE KEY: %s', profileName), ...
        'SUGGESTED BASELINE CONSTRAINTS/WEIGHTS (you may refine, keeping the rules):', ...
        jsonencode(struct('constraints',base.constraints, ...
                          'objective_weights',base.objective_weights, ...
                          'risk_tolerance',base.risk_tolerance),'PrettyPrint',true), ...
        '', 'POLICY TEXT:', policy_text, '', ...
        'Return only the JSON object described in the system instruction.'}, newline);

    % ---- Call Gemini (json-only) under the uniform auto|mock|live mode -------
    % Back-compat: opts.force_mock maps to mode='mock'. The actual network skip
    % happens centrally in gemini_call (mock short-circuit), so every caller is
    % uniform rather than each re-implementing its own offline branch.
    gmOpts = struct('json_only',true,'temperature',0.1);
    if forceMock; gmOpts.mode = 'mock'; end
    usedMock = false;
    config = struct();
    [txt, info] = gemini_call(sys, usr, gmOpts);
    if info.ok
        try
            config = jsondecode(localStripFences(txt));
        catch ME
            warning('gemini_policy_translator:parse', ...
                'Could not parse Gemini JSON (%s); using MOCK.', ME.message);
            usedMock = true;
        end
    else
        usedMock = true;
        if ~strcmp(info.status,'mock_mode')   % deliberate mock is not a warning
            warning('gemini_policy_translator:noLLM', ...
                'Gemini unavailable (%s); using MOCK policy config.', info.status);
        end
    end

    if usedMock
        config = localMockPolicy(base);
    end

    % ---- Validate / sanitize (governance enforced regardless of source) --
    config = localValidate(config, base, policy_text, usedMock);

    % ---- Save -------------------------------------------------------------
    txtOut = jsonencode(config, 'PrettyPrint', true);
    fid = fopen(outPath,'w');
    if fid < 0; error('gemini_policy_translator:fopen','Cannot write %s', outPath); end
    fwrite(fid, txtOut, 'char'); fclose(fid);

    tag = gemini_mode_tag(info, usedMock);
    fprintf('[gemini_policy_translator] (%s) profile=%s min_cleaning=%.1f -> %s\n', ...
        tag, config.profile, config.constraints.min_cleaning_score, outPath);
end

% ======================================================================
function config = localValidate(config, base, policy_text, usedMock)
% Enforce structural and governance constraints regardless of the source.
    if ~isfield(config,'policy_name') || isempty(config.policy_name)
        config.policy_name = base.policy_name;
    end
    if ~isfield(config,'profile') || isempty(config.profile)
        config.profile = base.profile;
    end
    config.profile = char(config.profile);

    % ---- Constraints: six fields; NaN (=> JSON null) where unconstrained.
    if ~isfield(config,'constraints') || ~isstruct(config.constraints)
        config.constraints = struct();
    end
    c  = config.constraints;
    bc = base.constraints;
    mc = localNumOr(c,'min_cleaning_score', bc.min_cleaning_score);
    if ~isfinite(mc); mc = bc.min_cleaning_score; end
    c.min_cleaning_score = max(95, mc);                       % governance floor
    capFields = {'max_COD_mgL','max_water_L','max_total_energy_kWh','max_CO2eq_kg'};
    for k = 1:numel(capFields)
        v = localNumOr(c, capFields{k}, bc.(capFields{k}));
        if isfinite(v) && v > 0; c.(capFields{k}) = v; else; c.(capFields{k}) = NaN; end
    end
    hr = localNumOr(c,'max_hygienic_risk', bc.max_hygienic_risk);
    if isfinite(hr); c.max_hygienic_risk = min(1, max(0, hr)); else; c.max_hygienic_risk = NaN; end
    config.constraints = orderfields(c, {'min_cleaning_score','max_COD_mgL', ...
        'max_hygienic_risk','max_water_L','max_total_energy_kWh','max_CO2eq_kg'});

    % ---- Objective weights: all five present, non-negative, sum to 1.
    % hygienic_risk is intentionally NOT a weight (it is collinear with
    % cleaning_score in the feasible region); it is enforced as max_hygienic_risk.
    wf = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg','cleaning_score'};
    if ~isfield(config,'objective_weights') || ~isstruct(config.objective_weights)
        config.objective_weights = struct();
    end
    w = zeros(1,numel(wf));
    for k = 1:numel(wf)
        w(k) = localNumOr(config.objective_weights, wf{k}, NaN);
        if ~isfinite(w(k)) || w(k) < 0; w(k) = base.objective_weights.(wf{k}); end
    end
    if sum(w) <= 0
        for k = 1:numel(wf); w(k) = base.objective_weights.(wf{k}); end
    end
    w = w / sum(w);
    % Round the first four and set the last as the remainder so the saved weights
    % sum to EXACTLY 1.0 (the schema promises exactly 1.0; avoid 0.9999 drift).
    rw = round(w, 4);
    rw(end) = round(1 - sum(rw(1:end-1)), 4);
    for k = 1:numel(wf); config.objective_weights.(wf{k}) = rw(k); end

    % ---- Metadata / governance flags.
    if isfield(config,'risk_tolerance') && ~isempty(config.risk_tolerance)
        rt = lower(char(config.risk_tolerance));
    else
        rt = base.risk_tolerance;
    end
    if ~ismember(rt, {'low','medium','high'}); rt = base.risk_tolerance; end
    config.risk_tolerance = rt;
    config.human_approval_required = true;                    % governance: always

    if ~isfield(config,'optimization_priority') || isempty(config.optimization_priority)
        config.optimization_priority = base.policy_name;
    end
    if ~isfield(config,'explanation'); config.explanation = ''; end
    % Scrub any operational directives from the free-text explanation (no footer
    % on this short config field) and label mock provenance generically.
    config.explanation = gemini_sanitize_report(char(config.explanation), false);
    if usedMock
        config.explanation = ['[MOCK] ' char(config.explanation)];
    end
    config.data_label = 'simulation-generated synthetic data - NOT real industrial data';
    config.source_policy_text = char(policy_text);

    % Stable key order for a clean, reviewable JSON artifact.
    config = orderfields(config, {'policy_name','profile','constraints', ...
        'objective_weights','risk_tolerance','human_approval_required', ...
        'optimization_priority','explanation','data_label','source_policy_text'});
end

% ======================================================================
function config = localMockPolicy(base)
% Deterministic fallback: the canonical profile, with a labelled explanation.
    config = struct();
    config.policy_name = base.policy_name;
    config.profile     = base.profile;
    config.constraints = base.constraints;
    config.objective_weights = base.objective_weights;
    config.risk_tolerance = base.risk_tolerance;
    config.human_approval_required = true;
    config.explanation = sprintf(['Deterministic profile-based translation (%s). ', ...
        'Weights and caps follow the canonical %s profile; hygiene floor enforced.'], ...
        base.profile, base.profile);
end

% ======================================================================
function name = localDetectProfile(policy_text)
% Map free-text policy language to the closest canonical profile by keywords.
    p = lower(char(policy_text));
    if contains(p,'hygien') || contains(p,'food safety') || contains(p,'high-risk') || contains(p,'pathogen')
        name = 'hygiene_priority';
    elseif contains(p,'cod') || contains(p,'wastewater') || contains(p,'discharge') || contains(p,'effluent')
        name = 'cod_discharge_limit';
    elseif contains(p,'carbon') || contains(p,'co2') || contains(p,'emission') || contains(p,'decarbon')
        name = 'carbon_reduction';
    elseif contains(p,'energy') || contains(p,'electricity') || contains(p,'price') || contains(p,'tariff')
        name = 'energy_price_spike';
    elseif contains(p,'water') || contains(p,'drought') || contains(p,'scarcit')
        name = 'water_scarcity';
    else
        name = 'balanced_default';
    end
end

% ======================================================================
function v = localNumOr(s, field, default)
%LOCALNUMOR Return a finite scalar from struct field, else the default.
%   JSON null/[] decode to empty; collapse to a single value so downstream
%   short-circuit logical tests never see a non-scalar operand.
    v = default;
    if isstruct(s) && isfield(s, field)
        x = s.(field);
        if isnumeric(x) && isscalar(x)
            v = x;
        elseif isnumeric(x) && ~isempty(x)
            v = x(1);
        end
    end
end

% ======================================================================
function s = localStripFences(s)
% Remove accidental markdown code fences around JSON.
    s = char(s);
    s = regexprep(s,'^\s*```[a-zA-Z]*\s*','');
    s = regexprep(s,'\s*```\s*$','');
end
