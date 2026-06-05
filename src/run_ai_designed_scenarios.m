% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function [Tbl, status] = run_ai_designed_scenarios(opts)
%RUN_AI_DESIGNED_SCENARIOS  Simulate the AI-designed CIP scenario batch.
%
%   [TBL, STATUS] = RUN_AI_DESIGNED_SCENARIOS() runs the scenarios in
%   results/ai_designed_scenarios.csv (produced by gemini_experiment_designer)
%   through the SAME Simulink digital twin used by run_cip_scenarios, using the
%   same robust execution logic (parsim + Fast Restart, serial fallback,
%   per-run status). Unlike run_cip_scenarios there is NO Monte-Carlo sampling:
%   the deck is exactly the AI-proposed (and MATLAB-clamped) experiment batch.
%
%   OPTS (all optional):
%       .scenarios_csv  results/ai_designed_scenarios.csv
%       .out_csv        data/dairy_cip_ai_designed_dataset.csv
%
%   If the scenario CSV is missing, gemini_experiment_designer is invoked first
%   (which itself falls back to a deterministic MOCK batch when Gemini is
%   unavailable), so this function never hard-fails on a missing artifact.
%
%   >>> THE OUTPUT IS SIMULATION-GENERATED SYNTHETIC DATA. <<<
%   Output columns: all inputs, all standard outputs, purpose, hypothesis_link,
%   expected_effect, simulation_status.
%
%   See also: GEMINI_EXPERIMENT_DESIGNER, RUN_CIP_SCENARIOS, VALIDATE_AI_HYPOTHESES.

    if nargin < 1 || isempty(opts); opts = struct(); end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    P = cip_parameters();

    resDir  = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
    dataDir = fullfile(root,'data');    if ~exist(dataDir,'dir'); mkdir(dataDir); end
    scenCsv = localOpt(opts,'scenarios_csv', fullfile(resDir,'ai_designed_scenarios.csv'));
    outCsv  = localOpt(opts,'out_csv',       fullfile(dataDir,'dairy_cip_ai_designed_dataset.csv'));

    % ---- Ensure the AI-designed deck exists (fallback: generate it) -----
    if exist(scenCsv,'file') ~= 2
        warning('run_ai_designed_scenarios:noDeck', ...
            'Scenario deck missing; invoking gemini_experiment_designer (mock-safe).');
        gemini_experiment_designer();
    end
    if exist(scenCsv,'file') ~= 2
        error('run_ai_designed_scenarios:stillNoDeck','Could not obtain %s', scenCsv);
    end
    Sc = readtable(scenCsv);
    N  = height(Sc);
    if N < 1; error('run_ai_designed_scenarios:empty','No scenarios in %s', scenCsv); end
    fprintf('[run_ai_designed_scenarios] Running %d AI-designed scenarios.\n', N);

    % ---- Build the clamped input matrix (defensive re-clamp) ------------
    vn = P.var_names;                       % 10 inputs, canonical order
    X = zeros(N, numel(vn));
    for k = 1:numel(vn)
        if ismember(vn{k}, Sc.Properties.VariableNames)
            col = Sc.(vn{k});
        else
            col = repmat((P.lb(k)+P.ub(k))/2, N, 1);   % missing -> midpoint
        end
        X(:,k) = min(P.ub(k), max(P.lb(k), col(:)));    % clamp to bounds
    end
    iT=1; iQ=2; ipre=3; ialk=4; iint=5; ifin=6; iNaOH=7; isoil=8; ihr=9; iwr=10;
    stopTime = X(:,ipre) + X(:,ialk) + X(:,iint) + X(:,ifin);
    T_in_C   = P.T_in_C;

    % Metadata columns (carried through to the output dataset).
    purpose        = localTextCol(Sc,'purpose',N);
    hypothesis_link= localTextCol(Sc,'hypothesis_link',N);
    expected_effect= localTextCol(Sc,'expected_effect',N);

    % ---- Load the model -------------------------------------------------
    mdl     = P.model_name;
    mdlFile = fullfile(root,'model',[mdl '.slx']);
    if exist(mdlFile,'file') ~= 4 && exist(mdlFile,'file') ~= 2
        error('run_ai_designed_scenarios:noModel', ...
            'Simulink model not found:\n  %s\nBuild it with build_model first.', mdlFile);
    end
    load_system(mdlFile);

    % ---- Build SimulationInput array (no assignin; model workspace) -----
    clear simIn
    simIn(1:N) = Simulink.SimulationInput(mdl);
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

    % ---- Run (parsim + Fast Restart, serial fallback) -------------------
    hasPCT = license('test','Distrib_Computing_Toolbox') && ~isempty(which('parsim'));
    simOut = []; ranParallel = false;
    if hasPCT
        try
            % No 'TransferBaseWorkspaceVariables': every scenario variable is
            % injected into the MODEL workspace via SimulationInput.setVariable, so
            % there is nothing to transfer from the base workspace (project
            % convention: no base-workspace state). Omitting it also clears the
            % XFRWSP advisory that flags this option for parsim.
            simOut = parsim(simIn, 'ShowProgress','on', 'UseFastRestart','on', ...
                'StopOnError','off');
            ranParallel = true;
        catch ME
            warning('run_ai_designed_scenarios:parsim','parsim failed (%s); serial.', ME.message);
            simOut = [];
        end
    end
    if isempty(simOut)
        try
            set_param(mdl,'FastRestart','on'); fastOK = true;
        catch
            fastOK = false;
        end
        cleanupObj = onCleanup(@() localTurnOffFastRestart(mdl, fastOK));
        tmp = cell(N,1);
        for i = 1:N
            try
                tmp{i} = sim(simIn(i));
            catch ME
                tmp{i} = ME;
            end
        end
        simOut = tmp;
        clear cleanupObj;   % restore FastRestart now (before extraction)
    end

    % ---- Extract outputs ------------------------------------------------
    scenario_id        = (1:N).';
    water_L            = nan(N,1);  thermal_energy_kWh = nan(N,1);
    pump_energy_kWh    = nan(N,1);  total_energy_kWh   = nan(N,1);
    COD_mgL            = nan(N,1);  NaOH_residual_mgL  = nan(N,1);
    CO2eq_kg           = nan(N,1);  cleaning_score     = nan(N,1);
    hygienic_risk      = nan(N,1);  EHPI               = nan(N,1);
    simulation_status  = strings(N,1);

    for i = 1:N
        [lo, errMsg] = localGetLogsout(simOut, i, ranParallel);
        if ~isempty(errMsg) || isempty(lo)
            simulation_status(i) = "failed"; continue;
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
            simulation_status(i)  = "success";
        catch
            simulation_status(i)  = "failed";
        end
    end

    % ---- Assemble + save ------------------------------------------------
    Tbl = table(scenario_id, ...
        X(:,iT), X(:,iQ), X(:,ipre), X(:,ialk), X(:,iint), X(:,ifin), ...
        X(:,iNaOH), X(:,isoil), X(:,ihr), X(:,iwr), repmat(T_in_C,N,1), stopTime, ...
        water_L, thermal_energy_kWh, pump_energy_kWh, total_energy_kWh, ...
        COD_mgL, NaOH_residual_mgL, CO2eq_kg, cleaning_score, hygienic_risk, EHPI, ...
        cellstr(simulation_status), purpose, hypothesis_link, expected_effect, ...
        'VariableNames', { ...
        'scenario_id','T_C','Q_m3h','t_pre','t_alk','t_int','t_final', ...
        'NaOH_pct','soil0','heat_rec','water_rec','T_in_C','stopTime', ...
        'water_L','thermal_energy_kWh','pump_energy_kWh','total_energy_kWh', ...
        'COD_mgL','NaOH_residual_mgL','CO2eq_kg','cleaning_score','hygienic_risk', ...
        'EHPI','simulation_status','purpose','hypothesis_link','expected_effect'});

    writetable(Tbl, outCsv);

    nSucc = sum(simulation_status=="success");
    status = struct('n',N,'n_success',nSucc,'n_failed',N-nSucc,'out_csv',outCsv);
    fprintf('[run_ai_designed_scenarios] Done. success=%d failed=%d -> %s\n', ...
        nSucc, N-nSucc, outCsv);
end

% ===== Local functions ===================================================
function v = getFinal(lo, name)
    el = lo.getElement(name);
    d  = el.Values.Data;
    v  = double(d(end));
end

function [lo, errMsg] = localGetLogsout(simOut, i, ranParallel)
    lo = []; errMsg = '';
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
            % best-effort restore; ignore
        end
    end
end

function c = localTextCol(T, name, N)
    c = repmat({''}, N, 1);
    if ismember(name, T.Properties.VariableNames)
        x = T.(name);
        if iscell(x); c = cellfun(@(e) char(string(e)), x, 'UniformOutput', false);
        elseif isstring(x); c = cellstr(x);
        elseif ischar(x); c = repmat({x}, N, 1);
        end
        c = c(:);
        if numel(c) ~= N; c = repmat({''}, N, 1); end
    end
end

function v = localOpt(opts, field, default)
    if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
        v = opts.(field);
    else
        v = default;
    end
end
