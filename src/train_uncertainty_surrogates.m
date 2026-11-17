% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% TRAIN_UNCERTAINTY_SURROGATES  Quantile-regression-forest surrogates with intervals.
%
%   Trains an uncertainty-aware surrogate per SAFETY-CRITICAL target using
%   quantile regression forests (TreeBagger + quantilePredict). For each target
%   it predicts a lower (q=0.05), median (q=0.50) and upper (q=0.95) quantile, so
%   the robust optimizer and the safety shield can reason with CONSERVATIVE
%   bounds instead of point estimates.
%
%   Targets: cleaning_score, COD_mgL, water_L, total_energy_kWh, CO2eq_kg,
%            hygienic_risk.
%
%   >>> Trained on SIMULATION-GENERATED SYNTHETIC DATA. The intervals quantify
%   SURROGATE uncertainty over the simulator, NOT real-world measurement
%   uncertainty. <<<
%
%   Dataset: data/dairy_cip_synthetic_dataset.csv by default; override with the
%   CIP_DATASET_CSV environment variable (e.g. the closed-loop combined dataset).
%
%   Outputs:
%     models/uncertainty_surrogates.mat       (qrf models, predictors, quantiles)
%     results/uncertainty_surrogate_metrics.csv (R2, RMSE, MAE, coverage, width)
%
%   See also: TRAIN_SURROGATE_MODELS, OPTIMIZE_CIP_ROBUST_PARETO, SAFETY_SHIELD.

%% ----- Paths and config -----------------------------------------------------
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();

csvPath = fullfile(root,'data','dairy_cip_synthetic_dataset.csv');
envCsv  = getenv('CIP_DATASET_CSV');
if ~isempty(envCsv) && exist(envCsv,'file')==2
    csvPath = envCsv;
    fprintf('[train_uncertainty_surrogates] Using dataset from CIP_DATASET_CSV: %s\n', csvPath);
end
resDir = fullfile(root,'results'); if ~exist(resDir,'dir'); mkdir(resDir); end
mdlDir = fullfile(root,'models');  if ~exist(mdlDir,'dir'); mkdir(mdlDir); end
matPath = fullfile(mdlDir,'uncertainty_surrogates.mat');
metPath = fullfile(resDir,'uncertainty_surrogate_metrics.csv');

if exist(csvPath,'file') ~= 2
    error('train_uncertainty_surrogates:noData','Dataset not found:\n  %s', csvPath);
end
if exist('TreeBagger','class') ~= 8 && exist('TreeBagger','file') == 0
    error('train_uncertainty_surrogates:noTreeBagger', ...
        'TreeBagger (Statistics and Machine Learning Toolbox) is required.');
end

%% ----- Load successful rows -------------------------------------------------
T = readtable(csvPath);
if ismember('simulation_status', T.Properties.VariableNames)
    T = T(string(T.simulation_status)=="success",:);
end
predictors = P.predictors;                                   % 10 inputs
targets    = {'cleaning_score','COD_mgL','water_L', ...
              'total_energy_kWh','CO2eq_kg','hygienic_risk'}; % critical + hygiene
targets    = targets(ismember(targets, T.Properties.VariableNames));
T = rmmissing(T(:, [predictors, targets]));
if height(T) < 50
    error('train_uncertainty_surrogates:tooFew','Only %d usable rows.', height(T));
end
fprintf('[train_uncertainty_surrogates] Training on %d rows.\n', height(T));

%% ----- Train/test split (same seed as the point surrogates) ----------------
rng(42);
cv = cvpartition(height(T),'HoldOut',0.20);
Xtr = T{training(cv), predictors};
Xte = T{test(cv),     predictors};

quantiles = [0.05 0.50 0.95];
nTrees    = 80;            % moderate: quantilePredict keeps the training leaves
qrf = struct();
metrics = table('Size',[numel(targets) 6], ...
    'VariableTypes',{'string','double','double','double','double','double'}, ...
    'VariableNames',{'target','R2','RMSE','MAE','coverage_90','mean_interval_width'});

for k = 1:numel(targets)
    tgt = targets{k};
    metrics.target(k) = string(tgt);
    ytr = T{training(cv), {tgt}};
    yte = T{test(cv),     {tgt}};
    try
        B = TreeBagger(nTrees, Xtr, ytr, 'Method','regression', ...
            'MinLeafSize',8, 'PredictorNames', predictors);
        qhat = quantilePredict(B, Xte, 'Quantile', quantiles);   % nTe x 3
        lo = qhat(:,1); med = qhat(:,2); hi = qhat(:,3);

        [r2,rmse,mae] = localMetrics(yte, med);
        cover = mean(yte >= lo & yte <= hi);
        width = mean(hi - lo);
        metrics.R2(k)=r2; metrics.RMSE(k)=rmse; metrics.MAE(k)=mae;
        metrics.coverage_90(k)=cover; metrics.mean_interval_width(k)=width;
        qrf.(tgt) = B;
        fprintf('   %-18s R2=%.3f RMSE=%.4g MAE=%.4g cover90=%.3f width=%.4g\n', ...
            tgt, r2, rmse, mae, cover, width);
    catch ME
        warning('train_uncertainty_surrogates:fail','Target %s failed: %s', tgt, ME.message);
        metrics.R2(k)=NaN; metrics.RMSE(k)=NaN; metrics.MAE(k)=NaN;
        metrics.coverage_90(k)=NaN; metrics.mean_interval_width(k)=NaN;
    end
end

%% ----- Save -----------------------------------------------------------------
data_label = 'simulation-generated synthetic data - surrogate uncertainty, NOT measurement uncertainty';
save(matPath, 'qrf', 'predictors', 'targets', 'quantiles', 'data_label');
writetable(metrics, metPath);
fprintf('[train_uncertainty_surrogates] Saved models -> %s\n', matPath);
fprintf('[train_uncertainty_surrogates] Saved metrics -> %s\n', metPath);
fprintf('[train_uncertainty_surrogates] NOTE: 90%% intervals; coverage near 0.90 is well-calibrated.\n');

%% ===== Local functions ======================================================
function [r2,rmse,mae] = localMetrics(y, yhat)
    y = y(:); yhat = yhat(:);
    err = y - yhat;
    sse = sum(err.^2); sst = sum((y - mean(y)).^2);
    r2   = 1 - sse / max(sst, eps);
    rmse = sqrt(mean(err.^2));
    mae  = mean(abs(err));
end
