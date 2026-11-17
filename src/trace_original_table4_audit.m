% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% Trace the conservative q0.10(CS) values of the original Table 4.
%  Hypothesis: the original audit propagated s0 ~ U(0.1,1) through the
%  quantile-regression-forest (QRF) uncertainty surrogate and used its lower
%  (q05) bound. Retrain the QRF exactly as in train_uncertainty_surrogates.m.
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here,'..','results');
T = readtable(localSrc(here,'dairy_cip_synthetic_dataset.csv'));
pred = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final','NaOH_pct','soil0','heat_rec','water_rec'};
rng(42); cv = cvpartition(height(T),'HoldOut',0.20);
Xtr = T{training(cv), pred};
B  = TreeBagger(80, Xtr, T{training(cv),'cleaning_score'}, 'Method','regression','MinLeafSize',8,'PredictorNames',pred);
BR = TreeBagger(80, Xtr, T{training(cv),'hygienic_risk'},  'Method','regression','MinLeafSize',8,'PredictorNames',pred);
J = jsondecode(fileread(fullfile(outDir,'policy_recipes_unrounded.json')));
profs = fieldnames(J); M = 1000; rng(42); s0 = 0.1 + 0.9*rand(M,1);
res = table();
for p = 1:numel(profs)
    x = J.(profs{p}); X = repmat(cellfun(@(v) x.(v), pred), M, 1); X(:,8) = s0;
    q  = quantilePredict(B,  X, 'Quantile', [0.05 0.50 0.95]);
    qr = quantilePredict(BR, X, 'Quantile', [0.05 0.50 0.95]);
    res = [res; table(string(profs{p}), quantile(q(:,1),0.10), quantile(q(:,2),0.10), ...
        quantile(qr(:,3),0.90), quantile(qr(:,2),0.90), ...
        'VariableNames',{'profile','q10_of_QRF_q05_CS','q10_of_QRF_median_CS','q90_of_QRF_q95_Rhyg','q90_of_QRF_median_Rhyg'})]; %#ok<AGROW>
end
disp(res); writetable(res, fullfile(outDir,'QRF_trace_of_original_Table4.csv'));


function p = localSrc(here, name)
%LOCALSRC Input file in data/ or results/ of the repository.
c = {fullfile(here,'..','data',name), fullfile(here,'..','results',name)};
p = c{find(cellfun(@isfile, c), 1)};
end
