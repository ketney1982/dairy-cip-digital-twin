% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9, 550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% Reproduce the 90% prediction-interval coverage of Table 2 with the
%  quantile regression forests of train_uncertainty_surrogates.m (80 trees,
%  MinLeafSize 8, q05/q95, same rng(42) 80/20 split, base dataset N = 5,000).
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here,'..','results');
T = readtable(localSrc(here,'dairy_cip_synthetic_dataset.csv'));
pred = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final','NaOH_pct','soil0','heat_rec','water_rec'};
tg = {'cleaning_score','COD_mgL','water_L','total_energy_kWh','CO2eq_kg','hygienic_risk'};  % original training order
rng(42); cv = cvpartition(height(T),'HoldOut',0.20);
Xtr = T{training(cv),pred}; Xte = T{test(cv),pred};
res = table();
for k = 1:numel(tg)
    ytr = T{training(cv),tg{k}}; yte = T{test(cv),tg{k}};
    B = TreeBagger(80, Xtr, ytr, 'Method','regression','MinLeafSize',8,'PredictorNames',pred);
    qh = quantilePredict(B, Xte, 'Quantile',[0.05 0.5 0.95]);
    res = [res; table(string(tg{k}), mean(yte>=qh(:,1) & yte<=qh(:,3)), mean(qh(:,3)-qh(:,1)), ...
        'VariableNames',{'target','coverage_90','mean_width'})]; %#ok<AGROW>
end
disp(res); writetable(res, fullfile(outDir,'QRF_PI_coverage_base5000.csv'));


function p = localSrc(here, name)
%LOCALSRC Input file in data/ or results/ of the repository.
c = {fullfile(here,'..','data',name), fullfile(here,'..','results',name)};
p = c{find(cellfun(@isfile, c), 1)};
end
