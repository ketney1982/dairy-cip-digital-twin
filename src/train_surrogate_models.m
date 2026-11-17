% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% TRAIN_SURROGATE_MODELS  Train ML surrogate regressors on the synthetic dataset.
%
%   Trains one fitrensemble (LSBoost) regression surrogate per environmental
%   target and evaluates accuracy (R2, RMSE, MAE, MAPE) on a held-out test set.
%
%   >>> These surrogates are trained on SIMULATION-GENERATED SYNTHETIC DATA. <<<
%   They approximate the Simulink digital twin so that optimization can query
%   thousands of candidate CIP recipes cheaply. They are NOT fitted to real
%   industrial measurements and carry the same caveats as the simulator.
%
%   Outputs:
%     results/surrogate_models.mat   (models, predictors, targets)
%     results/surrogate_metrics.csv  (per-target R2/RMSE/MAE/MAPE)
%     results/surrogate_pred_vs_obs.csv (held-out observed/predicted values)
%
%   See also: RUN_CIP_SCENARIOS, OPTIMIZE_CIP_PARETO.

%% ----- Paths and config -----------------------------------------------------
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(here);
P = cip_parameters();

% Default dataset is the canonical synthetic dataset. The optional environment
% variable CIP_DATASET_CSV lets a driver (e.g. run_ai_closed_loop_study) retrain
% on a COMBINED base + AI-designed dataset without modifying this stable script.
csvPath = fullfile(root,'data','dairy_cip_synthetic_dataset.csv');
envCsv  = getenv('CIP_DATASET_CSV');
if ~isempty(envCsv) && exist(envCsv,'file')==2
    csvPath = envCsv;
    fprintf('[train_surrogate_models] Using dataset from CIP_DATASET_CSV: %s\n', csvPath);
end
resDir  = fullfile(root,'results');  if ~exist(resDir,'dir'); mkdir(resDir); end
figDir  = fullfile(root,'figures');  if ~exist(figDir,'dir'); mkdir(figDir); end
matPath = fullfile(resDir,'surrogate_models.mat');
metPath = fullfile(resDir,'surrogate_metrics.csv');
predPath = fullfile(resDir,'surrogate_pred_vs_obs.csv');
figPath = fullfile(figDir,'fig_surrogate_pred_vs_obs.png');

if exist(csvPath,'file') ~= 2
    error('train_surrogate_models:noData','Dataset not found:\n  %s', csvPath);
end

%% ----- Load successful rows -------------------------------------------------
T = readtable(csvPath);
T = T(string(T.simulation_status)=="success",:);
% Drop rows with any missing predictor/target value.
predictors = P.predictors;        % 10 inputs
targets    = P.targets;           % 6 outputs
keepVars   = [predictors, targets];
T = rmmissing(T(:, keepVars));
if height(T) < 50
    error('train_surrogate_models:tooFew','Only %d usable rows; need more successful simulations.', height(T));
end
fprintf('[train_surrogate_models] Training on %d successful rows.\n', height(T));

%% ----- Train/test split -----------------------------------------------------
rng(42);
cv = cvpartition(height(T),'HoldOut',0.20);
Ttrain = T(training(cv),:);
Ttest  = T(test(cv),:);

%% ----- Train one surrogate per target ---------------------------------------
models  = struct();
metrics = table('Size',[numel(targets) 5], ...
    'VariableTypes',{'string','double','double','double','double'}, ...
    'VariableNames',{'target','R2','RMSE','MAE','MAPE'});
maxPredRows = height(Ttest) * numel(targets);
predTarget = strings(maxPredRows, 1);
predTestRow = nan(maxPredRows, 1);
predObserved = nan(maxPredRows, 1);
predPredicted = nan(maxPredRows, 1);
predCursor = 0;

for k = 1:numel(targets)
    tgt = targets{k};
    metrics.target(k) = string(tgt);
    try
        mdl = fitrensemble(Ttrain, tgt, ...
            'PredictorNames', predictors, ...
            'Method','LSBoost', ...
            'NumLearningCycles',200, ...
            'LearnRate',0.1, ...
            'Learners',templateTree('MaxNumSplits',20));
        models.(tgt) = compact(mdl);

        yObs = Ttest.(tgt);
        yHat = predict(mdl, Ttest);
        nPred = numel(yObs);
        rows = predCursor + (1:nPred);
        predTarget(rows) = string(tgt);
        predTestRow(rows) = (1:nPred).';
        predObserved(rows) = double(yObs(:));
        predPredicted(rows) = double(yHat(:));
        predCursor = predCursor + nPred;
        [r2,rmse,mae,mape] = localMetrics(yObs, yHat);
        metrics.R2(k)=r2; metrics.RMSE(k)=rmse; metrics.MAE(k)=mae; metrics.MAPE(k)=mape;
        fprintf('   %-18s R2=%.3f RMSE=%.4g MAE=%.4g MAPE=%.2f%%\n', tgt, r2, rmse, mae, mape);
    catch ME
        warning('train_surrogate_models:trainFail','Target %s failed: %s', tgt, ME.message);
        metrics.R2(k)=NaN; metrics.RMSE(k)=NaN; metrics.MAE(k)=NaN; metrics.MAPE(k)=NaN;
    end
end

%% ----- Save models and metrics ----------------------------------------------
save(matPath,'models','predictors','targets');
predRows = table( ...
    predTarget(1:predCursor), ...
    predTestRow(1:predCursor), ...
    predObserved(1:predCursor), ...
    predPredicted(1:predCursor), ...
    'VariableNames', {'target','test_row','observed','predicted'});
writetable(metrics, metPath);
writetable(predRows, predPath);
fprintf('[train_surrogate_models] Saved models -> %s\n', matPath);
fprintf('[train_surrogate_models] Saved metrics -> %s\n', metPath);
fprintf('[train_surrogate_models] Saved held-out predictions -> %s\n', predPath);

%% ----- Predicted vs observed figure -----------------------------------------
if localEnvBool('CIP_MATLAB_FIGURES', false)
try
    f = figure('Visible','off','Position',[100 100 1200 700]);
    nCol = 3; nRow = ceil(numel(targets)/nCol);   % adapt grid to target count
    tl = tiledlayout(f,nRow,nCol,'Padding','compact','TileSpacing','compact');
    title(tl,'Surrogate predicted vs observed (held-out test set; SYNTHETIC data)');
    for k = 1:numel(targets)
        tgt = targets{k};
        nexttile;
        if isfield(models,tgt)
            yObs = Ttest.(tgt); yHat = predict(models.(tgt), Ttest);
            scatter(yObs,yHat,8,'filled','MarkerFaceAlpha',0.25); hold on;
            lo = min([yObs;yHat]); hi = max([yObs;yHat]);
            plot([lo hi],[lo hi],'k--','LineWidth',1);
            axis tight; grid on;
            xlabel(['observed ' strrep(tgt,'_','\_')]);
            ylabel('predicted');
            title(sprintf('%s (R^2=%.3f)', strrep(tgt,'_','\_'), metrics.R2(k)));
        else
            title([strrep(tgt,'_','\_') ' (failed)']);
        end
    end
    exportgraphics(f, figPath, 'Resolution',200);
    close(f);
    fprintf('[train_surrogate_models] Saved figure -> %s\n', figPath);
catch ME
    warning('train_surrogate_models:fig','Could not create pred-vs-obs figure: %s', ME.message);
end
else
    fprintf('[train_surrogate_models] Skipped MATLAB figure (Python manuscript figures use surrogate_pred_vs_obs.csv).\n');
end

%% ===== Local functions ======================================================
function [r2,rmse,mae,mape] = localMetrics(y, yhat)
    y = y(:); yhat = yhat(:);
    err = y - yhat;
    sse = sum(err.^2);
    sst = sum((y - mean(y)).^2);
    r2   = 1 - sse / max(sst, eps);
    rmse = sqrt(mean(err.^2));
    mae  = mean(abs(err));
    % MAPE excludes near-zero observations to avoid division blow-up.
    thr = max(1e-6, 0.001*max(abs(y)));
    m = abs(y) > thr;
    if any(m)
        mape = 100 * mean(abs(err(m) ./ y(m)));
    else
        mape = NaN;
    end
end

function v = localEnvBool(name, default)
%LOCALENVBOOL Return a logical from an env var ('true'/'1' -> true, 'false'/'0' -> false).
    v = default;
    s = lower(strtrim(getenv(name)));
    if strcmp(s,'true') || strcmp(s,'1')
        v = true;
    elseif strcmp(s,'false') || strcmp(s,'0')
        v = false;
    end
end
