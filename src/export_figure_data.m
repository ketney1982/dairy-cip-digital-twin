% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function export_figure_data()
%EXPORT_FIGURE_DATA  Compute, in MATLAB, every DERIVED quantity the Python
%   manuscript figures need, and write it to dedicated CSVs under results/.
%   The Python layer then only reads + draws — no statistic is computed in
%   Python (single source of truth = MATLAB). Outputs:
%     results/fig2_kde.csv          KPI kernel-density curves (Fig 2)
%     results/fig2_dist_stats.csv   KPI medians + % meeting hygiene floor (Fig 2)
%     results/fig3_correlation.csv  Pearson correlation matrix (Fig 3)
%     results/fig4_sensitivity.csv  binned mean +/- SEM and Pearson r (Fig 4)
%     results/figS1_phase_summary.csv  per-recipe phase durations + final KPIs (Fig S1)
%
%   The formulas EXACTLY replicate the prior Python helpers (Silverman-bandwidth
%   Gaussian KDE; 14 equal-width bins with mean and standard error; Pearson r;
%   phase-segment tiling) so the figures are unchanged — only their provenance
%   moves to MATLAB. All data are SIMULATION-GENERATED SYNTHETIC (proof-of-
%   concept; coefficients not calibrated against plant data).

    here   = fileparts(mfilename('fullpath'));
    addpath(here);
    root   = fullfile(here, '..');
    resDir = fullfile(root, 'results');
    dataDir = fullfile(root, 'data');

    Mp = cip_model_params();
    floorCS = Mp.min_cleaning_score;

    % --- Load synthetic dataset, success rows only (mirrors cs.load_dataset) ---
    ds = readtable(fullfile(dataDir, 'dairy_cip_synthetic_dataset.csv'));
    if ismember('simulation_status', ds.Properties.VariableNames)
        ds = ds(string(ds.simulation_status) == "success", :);
    end

    %% ----- Fig 2: KPI kernel-density estimates + distribution stats ----------
    kpis = {'cleaning_score','COD_mgL','total_energy_kWh','water_L','CO2eq_kg','EHPI'};
    kdeParts = cell(numel(kpis),1);
    statKpi  = strings(numel(kpis),1);
    statMed  = nan(numel(kpis),1);
    statFrac = nan(numel(kpis),1);
    for i = 1:numel(kpis)
        statKpi(i) = string(kpis{i});
        if ~ismember(kpis{i}, ds.Properties.VariableNames); continue; end
        v = ds.(kpis{i}); v = v(isfinite(v));
        if isempty(v); continue; end
        xg   = linspace(min(v), max(v), 300)';
        dens = localKde(v, xg);
        kdeParts{i} = table(repmat(string(kpis{i}),300,1), xg, dens, ...
            'VariableNames', {'kpi','x','density'});
        statMed(i) = median(v);
        if strcmp(kpis{i}, 'cleaning_score')
            statFrac(i) = 100 * mean(v >= floorCS);
        end
    end
    writetable(vertcat(kdeParts{:}), fullfile(resDir,'fig2_kde.csv'));
    writetable(table(statKpi, statMed, statFrac, ...
        'VariableNames', {'kpi','median','frac_ge_floor'}), ...
        fullfile(resDir,'fig2_dist_stats.csv'));

    %% ----- Fig 3: Pearson correlation matrix ---------------------------------
    order = {'T_C','Q_m3h','t_pre','t_alk','t_int','t_final','NaOH_pct','soil0', ...
             'heat_rec','water_rec','water_L','total_energy_kWh','COD_mgL', ...
             'CO2eq_kg','cleaning_score','hygienic_risk','EHPI'};
    order = order(ismember(order, ds.Properties.VariableNames));
    C = corr(ds{:, order}, 'Rows', 'pairwise');
    Ctab = array2table(C, 'VariableNames', order);
    Ctab = addvars(Ctab, string(order(:)), 'Before', 1, 'NewVariableNames', 'variable');
    writetable(Ctab, fullfile(resDir,'fig3_correlation.csv'));

    %% ----- Fig 4: binned mean +/- SEM and Pearson r per panel ----------------
    panels = {'soil0','cleaning_score'; 't_alk','cleaning_score'; 'T_C','cleaning_score'; ...
              'soil0','COD_mgL'; 'heat_rec','total_energy_kWh'; 'water_rec','water_L'};
    t4parts = cell(size(panels,1),1);
    for p = 1:size(panels,1)
        xk = panels{p,1}; yk = panels{p,2};
        x = ds.(xk); y = ds.(yk);
        m = isfinite(x) & isfinite(y); x = x(m); y = y(m);
        [cx, cy, cse] = localBinnedMeanSem(x, y, 14);
        r  = corr(x, y);
        nb = numel(cx);
        t4parts{p} = table(repmat(p,nb,1), repmat(string(xk),nb,1), ...
            repmat(string(yk),nb,1), cx, cy, cse, repmat(r,nb,1), ...
            'VariableNames', {'panel','driver','response','x_center','mean_y','sem_y','r'});
    end
    writetable(vertcat(t4parts{:}), fullfile(resDir,'fig4_sensitivity.csv'));

    %% ----- Fig S1: per-recipe phase durations + final KPIs -------------------
    recipes = {'baseline','water_saving','energy_saving','hygiene_priority', ...
               'high_soil_stress','low_cod_policy'};
    s1parts = cell(numel(recipes),1);
    for i = 1:numel(recipes)
        f = fullfile(resDir, ['demo_timeseries_' recipes{i} '.csv']);
        if ~isfile(f); continue; end
        T = readtable(f);
        t = T.time_s; ph = round(T.phase_id); tend = t(end);
        present = find([any(ph==1), any(ph==2), any(ph==3), any(ph==4)]);
        startsP = arrayfun(@(k) t(find(ph==k,1,'first')), present);
        durP = diff([startsP(:); tend]);
        if ~isempty(durP); durP(1) = durP(1) + startsP(1); end   % anchor first phase at t=0
        dur = zeros(1,4); dur(present) = durP;
        s1parts{i} = table(string(recipes{i}), dur(1), dur(2), dur(3), dur(4), tend, ...
            T.cleaning_score(end), T.total_energy_kWh(end), T.COD_mgL(end), T.CO2eq_kg(end), ...
            'VariableNames', {'recipe','dur_pre','dur_alk','dur_int','dur_final','t_end', ...
                              'cleaning_score','total_energy_kWh','COD_mgL','CO2eq_kg'});
    end
    writetable(vertcat(s1parts{:}), fullfile(resDir,'figS1_phase_summary.csv'));

    fprintf('[export_figure_data] Wrote fig2_kde, fig2_dist_stats, fig3_correlation, fig4_sensitivity, figS1_phase_summary -> %s\n', resDir);
end


function dens = localKde(data, xg)
%LOCALKDE  Gaussian KDE with Silverman bandwidth (matches the prior native_kde).
    data = data(:); n = numel(data);
    if n == 0; dens = zeros(size(xg)); return; end
    if n > 1; s = std(data); else; s = 1; end          % std uses N-1 (ddof=1)
    if s == 0; s = 1; end
    bw = 1.06 * s * n^(-0.2);
    D = (xg(:) - data(:)') / bw;
    dens = mean(exp(-0.5 * D.^2), 2) / (sqrt(2*pi) * bw);
end


function [cx, cy, csem] = localBinnedMeanSem(x, y, nbins)
%LOCALBINNEDMEANSEM  Equal-width binned mean and SEM (matches binned_mean_with_sem).
    x = x(:); y = y(:);
    edges = linspace(min(x), max(x), nbins + 1);
    idx = discretize(x, edges);                 % 1..nbins (max -> last bin)
    cx = nan(nbins,1); cy = nan(nbins,1); csem = nan(nbins,1);
    for b = 1:nbins
        sel = (idx == b);
        if any(sel)
            cx(b) = mean(x(sel));
            cy(b) = mean(y(sel));
            if sum(sel) > 1
                csem(b) = std(y(sel)) / sqrt(sum(sel));
            else
                csem(b) = 0;
            end
        end
    end
    ok = isfinite(cx) & isfinite(cy);
    cx = cx(ok); cy = cy(ok); csem = csem(ok);
    csem(~isfinite(csem)) = 0;
end
