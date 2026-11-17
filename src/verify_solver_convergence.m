% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% VERIFY_SOLVER_CONVERGENCE  Simulink solver settings vs the closed-form solution (revision R1).
%
%   The closed form S(t_end) = s0*exp(-(k_pre t_pre + k_alk t_alk + k_rinse (t_int + t_final)))
%   (Eq. 4a; src/cip_closed_form.py) is the exact solution of the soil ODE of the Simulink
%   model, and all audit verdicts of the manuscript are computed with it. The 5,000 base
%   scenarios were integrated with the build settings of src/build_model.m (ode23t,
%   RelTol 1e-4, MaxStep 5 s), which leave a deviation of up to 0.25 CS points
%   (Supplementary Table S11). This script re-runs selected scenarios with refined solver
%   settings to show that the Simulink result converges to the closed form, i.e. that the
%   deviation is an integration error and that the closed-form verdicts do not depend on
%   solver settings.
%
%   Scenarios
%     largest_deviation : the 100 base scenarios with the largest default deviation
%     near_floor        : 100 random base scenarios with closed-form CS of 94-97 %
%     recipe_*          : balanced-default and hygiene-priority policy recipes and the
%                         audit-then-select U3 recipes without and with v >= 1.5 m/s,
%                         each at s0 = 0.5, 0.91 and 1.0
%   Settings
%     default   : ode23t, RelTol 1e-4, MaxStep 5 s (as for the 5,000 base scenarios)
%     refined   : ode23t, RelTol 1e-7, AbsTol 1e-9, MaxStep 0.5 s
%     reference : ode45,  RelTol 1e-10, AbsTol 1e-12, MaxStep 0.1 s
%
%   Output: results/solver_convergence.csv (one row per scenario and setting)

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();
M = cip_model_params();
mdl = P.model_name;
load_system(fullfile(root, 'model', [mdl '.slx']));
V = P.var_names;

%% ----- scenarios ------------------------------------------------------------
D = readtable(fullfile(root, 'data', 'dairy_cip_synthetic_dataset.csv'));
Xb = D{:, V};
csB = closedFormCS(Xb, M, V);
dB = D.cleaning_score - csB;
[~, iBig] = maxk(abs(dB), 100);
near = find(csB >= 94 & csB <= 97);
rng(7);
iNear = near(randperm(numel(near), 100));

C = readtable(fullfile(root, 'results', 'conservative_confirmation.csv'), 'TextType', 'string');
pick = @(scr, prof) C(C.screening == scr & C.profile == prof, :);
R = [pick("policy recipe (Table 4)", "balanced_default"); pick("policy recipe (Table 4)", "hygiene_priority"); ...
     pick("audit-then-select, U3 (Table 5)", "balanced_default"); ...
     pick("audit-then-select, U3, v >= 1.5 m/s (Table 5)", "balanced_default")];
R = R([1 3 5 6], :);      % the policy-recipe rows appear once per uncertainty set
rName = ["recipe_balanced_default_policy", "recipe_hygiene_priority_policy", ...
         "recipe_audit_then_select_U3", "recipe_audit_then_select_U3_v1p5"];
s0List = [0.5 0.91 1.0];
Xr = zeros(numel(rName) * numel(s0List), numel(V)); gR = strings(size(Xr, 1), 1); k = 0;
for i = 1:numel(rName)
    for s0 = s0List
        k = k + 1;
        Xr(k, :) = R{i, V};
        Xr(k, strcmp(V, 'soil0')) = s0;
        gR(k) = rName(i);
    end
end
X = [Xb(iBig, :); Xb(iNear, :); Xr];
group = [repmat("largest_deviation", 100, 1); repmat("near_floor", 100, 1); gR];
baseId = [iBig; iNear; nan(numel(gR), 1)];
csCF = closedFormCS(X, M, V);
nX = size(X, 1);

%% ----- solver settings ------------------------------------------------------
S = struct('name', {'default', 'refined', 'reference'}, ...
           'solver', {'ode23t', 'ode23t', 'ode45'}, ...
           'reltol', {'1e-4', '1e-7', '1e-10'}, ...
           'abstol', {'auto', '1e-9', '1e-12'}, ...
           'maxstep', {'5', '0.5', '0.1'});
CS = nan(nX, numel(S)); wall = nan(1, numel(S));
for j = 1:numel(S)
    in(1:nX) = Simulink.SimulationInput(mdl);
    for i = 1:nX
        x = X(i, :);
        s = Simulink.SimulationInput(mdl);
        for v = 1:numel(V)
            s = s.setVariable(V{v}, x(v), 'Workspace', mdl);
        end
        s = s.setVariable('T_in_C', P.T_in_C, 'Workspace', mdl);
        s = s.setModelParameter('StopTime', num2str(sum(x(3:6)), 17), ...
            'Solver', S(j).solver, 'RelTol', S(j).reltol, 'AbsTol', S(j).abstol, ...
            'MaxStep', S(j).maxstep, 'SignalLogging', 'on', 'SignalLoggingName', 'logsout');
        in(i) = s;
    end
    tic;
    % Fast Restart only for the default settings: solver tolerances and MaxStep are not
    % tunable between Fast Restart runs, so the refined settings recompile for every run.
    fr = 'off'; if j == 1, fr = 'on'; end
    out = sim(in, 'UseFastRestart', fr, 'ShowProgress', 'off');
    bad = find(arrayfun(@(o) ~isempty(o.ErrorMessage), out));
    if ~isempty(bad)
        error('verify_solver_convergence:failed', '%d failed runs (%s): %s', numel(bad), S(j).name, ...
            out(bad(1)).ErrorMessage);
    end
    wall(j) = toc / nX;
    for i = 1:nX
        d = out(i).logsout.get('cleaning_score').Values.Data;
        CS(i, j) = double(d(end));
    end
    fprintf('[verify_solver_convergence] %s: %.3f s per run, max |dCS| = %.5f points\n', ...
        S(j).name, wall(j), max(abs(CS(:, j) - csCF)));
    clear in out
end

%% ----- output -----------------------------------------------------------------
T = table(group, baseId, csCF, CS(:, 1), CS(:, 2), CS(:, 3), ...
    CS(:, 1) - csCF, CS(:, 2) - csCF, CS(:, 3) - csCF, ...
    'VariableNames', {'group', 'base_scenario_id', 'CS_closed_form', 'CS_default', ...
    'CS_refined', 'CS_reference', 'dCS_default', 'dCS_refined', 'dCS_reference'});
T = [T, array2table(X, 'VariableNames', V)];
writetable(T, fullfile(root, 'results', 'solver_convergence.csv'));
for g = unique(group)'
    m = group == g;
    fprintf('%-34s n=%3d  max|dCS| default %.5f  refined %.5f  reference %.6f\n', g, sum(m), ...
        max(abs(T.dCS_default(m))), max(abs(T.dCS_refined(m))), max(abs(T.dCS_reference(m))));
end
fprintf('wall time per run (s): default %.3f, refined %.3f, reference %.3f\n', wall);

function cs = closedFormCS(X, M, V)
%CLOSEDFORMCS Closed-form cleaning score (Eq. 4a and Eq. 10).
c = @(n) X(:, strcmp(V, n));
fQ = (c('Q_m3h') / M.Q_ref) .^ M.beta_Q;
kPre = M.k_cal * M.k_pre_base * fQ;
kAlk = M.k_cal * M.k_alk_base * exp(M.alpha_T * (c('T_C') - M.T_ref)) .* fQ .* (c('NaOH_pct') / M.NaOH_ref) .^ M.gamma_NaOH;
kRin = M.k_cal * M.k_rinse_base * fQ;
Send = c('soil0') .* exp(-(kPre .* c('t_pre') + kAlk .* c('t_alk') + kRin .* (c('t_int') + c('t_final'))));
cs = min(max(100 * (1 - Send), 0), 100);
end
