% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% Surrogate validation (random, 5-fold, leave-region-out), surrogate-based
%  Monte Carlo audit of the policy recipes and computational timing.
%  Uses the original dataset and the original LSBoost settings
%  (200 cycles, LearnRate 0.1, MaxNumSplits 20, rng(42)).
%  Author: Ketney Otto (revision R1 evidence package)

here    = fileparts(mfilename('fullpath'));
repo    = fullfile(here,'..');                             % repository root (this file is in src/)
outDir  = fullfile(here,'..','results');
addpath(fullfile(repo,'src'));

T = readtable(localSrc(here,'dairy_cip_synthetic_dataset.csv'));
pred = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final','NaOH_pct','soil0','heat_rec','water_rec'};
tgts = {'water_L','total_energy_kWh','COD_mgL','CO2eq_kg','cleaning_score','EHPI','hygienic_risk'};
tmpl = templateTree('MaxNumSplits',20);
fitfun = @(Ttr,tg) fitrensemble(Ttr, tg, 'PredictorNames', pred, 'Method','LSBoost', ...
    'NumLearningCycles',200, 'LearnRate',0.1, 'Learners',tmpl);
met = @(y,yh) [1-sum((y-yh).^2)/sum((y-mean(y)).^2), sqrt(mean((y-yh).^2)), mean(abs(y-yh))];

%% 1) original random 80/20 split (reproduction)
rng(42); cv = cvpartition(height(T),'HoldOut',0.20);
Ttr = T(training(cv),:); Tte = T(test(cv),:);
models = struct(); R = [];
tTrain = tic;
for k = 1:numel(tgts)
    m = fitfun(Ttr, tgts{k}); models.(tgts{k}) = compact(m);
    R = [R; met(Tte.(tgts{k}), predict(m,Tte))]; %#ok<AGROW>
end
trainTime = toc(tTrain);
split = repmat("random_80_20",numel(tgts),1);
res = table(split, string(tgts'), R(:,1), R(:,2), R(:,3), 'VariableNames',{'split','target','R2','RMSE','MAE'});

%% 2) 5-fold cross-validation (random, scenario-wise)
rng(42); cv5 = cvpartition(height(T),'KFold',5);
R5 = zeros(numel(tgts),3,5);
for f = 1:5
    a = T(training(cv5,f),:); b = T(test(cv5,f),:);
    for k = 1:numel(tgts)
        m = fitfun(a, tgts{k}); R5(k,:,f) = met(b.(tgts{k}), predict(m,b));
    end
end
mu = mean(R5,3); sd = std(R5,0,3);
cvTab = table(string(tgts'), mu(:,1), sd(:,1), mu(:,2), sd(:,2), mu(:,3), sd(:,3), ...
    'VariableNames',{'target','R2_mean','R2_sd','RMSE_mean','RMSE_sd','MAE_mean','MAE_sd'});
writetable(cvTab, fullfile(outDir,'surrogate_5fold_cv.csv'));

%% 3) leave-region-out (extrapolation) splits: train outside, test inside region
regions = {
  'soil0_ge_0.85',   T.soil0   >= 0.85
  'T_ge_79C',        T.T_C     >= 79
  'Q_ge_2.6',        T.Q_m3h   >= 2.6
  't_alk_le_500s',   T.t_alk   <= 500
  'NaOH_ge_2.2',     T.NaOH_pct >= 2.2 };
for r = 1:size(regions,1)
    inR = regions{r,2};
    a = T(~inR,:); b = T(inR,:);
    for k = 1:numel(tgts)
        m = fitfun(a, tgts{k}); v = met(b.(tgts{k}), predict(m,b));
        res = [res; {string(['leave_region_out:' regions{r,1}]), string(tgts{k}), v(1), v(2), v(3)}]; %#ok<AGROW>
    end
    fprintf('region %s: n_test=%d\n', regions{r,1}, sum(inR));
end
writetable(res, fullfile(outDir,'surrogate_random_and_region_splits.csv'));

%% 4) surrogate-based MC audit of the policy recipes (U0: s0 ~ U(0.1,1))
J = jsondecode(fileread(fullfile(outDir,'policy_recipes_unrounded.json')));
profs = fieldnames(J); M = 1000;
rng(42); s0 = 0.1 + 0.9*rand(M,1);
aud = table();
for p = 1:numel(profs)
    x = J.(profs{p});
    X = repmat(cellfun(@(v) x.(v), pred), M, 1); X(:,8) = s0;
    Tx = array2table(X,'VariableNames',pred);
    cs = min(100,max(0,predict(models.cleaning_score,Tx)));
    rh = min(1,max(0,predict(models.hygienic_risk,Tx)));
    % exact simulator on the same draws (closed form)
    P = cip_model_params();
    fQ = (X(:,2)/P.Q_ref).^P.beta_Q;
    ex = P.k_cal*P.k_pre_base*fQ.*X(:,3) + P.k_cal*P.k_alk_base*exp(P.alpha_T*(X(:,1)-P.T_ref)).*fQ.*(X(:,7)/P.NaOH_ref).^P.gamma_NaOH.*X(:,4) ...
       + P.k_cal*P.k_rinse_base*fQ.*(X(:,5)+X(:,6));
    csSim = 100*(1 - X(:,8).*exp(-ex));
    aud = [aud; table(string(profs{p}), quantile(cs,0.10), quantile(rh,0.90), quantile(csSim,0.10), ...
        'VariableNames',{'profile','surrogate_q10_CS','surrogate_q90_Rhyg','simulator_q10_CS'})]; %#ok<AGROW>
end
writetable(aud, fullfile(outDir,'surrogate_vs_simulator_MC_audit_U0.csv'));
disp(aud)

%% 5) timing
Xq = array2table(T{1:1000,pred},'VariableNames',pred);
tic; for rep = 1:5; for k = 1:numel(tgts); predict(models.(tgts{k}), Xq); end; end
tSurr = toc/5/1000;          % s per scenario, all 7 targets
mdl = 'dairy_cip_digital_twin';
load_system(fullfile(repo,'model',[mdl '.slx']));
nS = 20; in(1:nS) = Simulink.SimulationInput(mdl);
for i = 1:nS
    r = T(i,:);
    s = Simulink.SimulationInput(mdl);
    for v = pred; s = s.setVariable(v{1}, r.(v{1}), 'Workspace', mdl); end
    s = s.setVariable('T_in_C', 15, 'Workspace', mdl);
    s = s.setModelParameter('StopTime', num2str(r.t_pre+r.t_alk+r.t_int+r.t_final));
    in(i) = s;
end
tic; out1 = sim(in(1)); tFirst = toc;                                   %#ok<NASGU>
tic; out = sim(in(2:end), 'UseFastRestart','on', 'ShowProgress','off'); tFR = toc/(nS-1);  %#ok<NASGU>
tic; for i = 2:6; o = sim(in(i)); end; tSerial = toc/5;                 %#ok<NASGU>
timing = table(trainTime, tSurr, tFirst, tFR, tSerial, ...
    'VariableNames',{'LSBoost_training_7targets_s','LSBoost_predict_s_per_scenario_7targets', ...
    'Simulink_first_run_incl_compile_s','Simulink_fastrestart_s_per_run','Simulink_normal_s_per_run'});
writetable(timing, fullfile(outDir,'timing_matlab.csv'));
disp(timing); disp(res); disp(cvTab);
close_system(mdl, 0);


function p = localSrc(here, name)
%LOCALSRC Input file in data/ or results/ of the repository.
c = {fullfile(here,'..','data',name), fullfile(here,'..','results',name)};
p = c{find(cellfun(@isfile, c), 1)};
end
