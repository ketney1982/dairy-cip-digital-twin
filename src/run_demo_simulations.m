% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

%% RUN_DEMO_SIMULATIONS Run fixed recipe demonstrations for the CIP twin.
%
%   Runs six inspectable synthetic CIP recipes with Simulink.SimulationInput,
%   verifies logsout, and writes CSV summary/time-series artifacts for the
%   Python manuscript figure pipeline. MATLAB demo figures/model diagrams are
%   optional and require CIP_MATLAB_FIGURES=true.
%
%   All outputs are SIMULATION-GENERATED SYNTHETIC DATA from an uncalibrated
%   proof-of-concept model. They are not real measurements and are not suitable
%   for operational control.
%
%   See also BUILD_MODEL, RUN_CIP_SCENARIOS.

%% Paths and setup
here = fileparts(mfilename("fullpath"));
root = fileparts(here);
addpath(here);

P = cip_parameters();
mdl = P.model_name;
mdlFile = fullfile(root, "model", mdl + ".slx");
resultsDir = fullfile(root, "results");
figuresDir = fullfile(root, "figures");
writeMatlabFigures = localEnvBool("CIP_MATLAB_FIGURES", false);
if ~exist(resultsDir, "dir")
    mkdir(resultsDir);
end
if writeMatlabFigures && ~exist(figuresDir, "dir")
    mkdir(figuresDir);
end

if exist(mdlFile, "file") ~= 2 && exist(mdlFile, "file") ~= 4
    build_model();
end
load_system(mdlFile);
cleanupObj = onCleanup(@() close_system(mdl, 0));

recipes = localDemoRecipes(P);
summaryRows = repmat(localEmptySummary(), numel(recipes), 1);

%% Run fixed demo recipes
for idx = 1:numel(recipes)
    recipe = recipes(idx);
    stopTime = recipe.t_pre + recipe.t_alk + recipe.t_int + recipe.t_final;

    in = Simulink.SimulationInput(mdl);
    in = localSetRecipeVariable(in, mdl, "T_C", recipe.T_C);
    in = localSetRecipeVariable(in, mdl, "Q_m3h", recipe.Q_m3h);
    in = localSetRecipeVariable(in, mdl, "t_pre", recipe.t_pre);
    in = localSetRecipeVariable(in, mdl, "t_alk", recipe.t_alk);
    in = localSetRecipeVariable(in, mdl, "t_int", recipe.t_int);
    in = localSetRecipeVariable(in, mdl, "t_final", recipe.t_final);
    in = localSetRecipeVariable(in, mdl, "NaOH_pct", recipe.NaOH_pct);
    in = localSetRecipeVariable(in, mdl, "soil0", recipe.soil0);
    in = localSetRecipeVariable(in, mdl, "heat_rec", recipe.heat_rec);
    in = localSetRecipeVariable(in, mdl, "water_rec", recipe.water_rec);
    in = localSetRecipeVariable(in, mdl, "T_in_C", recipe.T_in_C);
    in = in.setModelParameter("StopTime", num2str(stopTime));
    in = in.setModelParameter("SignalLogging", "on");
    in = in.setModelParameter("SignalLoggingName", "logsout");

    out = sim(in);
    lo = out.logsout;
    localAssertLogsout(lo, P.logged_signals);

    summaryRows(idx) = localSummaryRow(recipe, stopTime, lo, P);
    timeSeriesTable = localTimeseriesTable(lo);

    scenarioId = localFileId(recipe.scenario);
    csvPath = fullfile(resultsDir, "demo_timeseries_" + scenarioId + ".csv");
    writetable(timeSeriesTable, csvPath);
    if writeMatlabFigures
        localPlotScenario(timeSeriesTable, recipe.scenario, figuresDir);
    end

    fprintf("[run_demo_simulations] %s: cleaning=%.2f COD=%.2f water=%.1f energy=%.2f\n", ...
        recipe.scenario, summaryRows(idx).cleaning_score, summaryRows(idx).COD_mgL, ...
        summaryRows(idx).water_L, summaryRows(idx).total_energy_kWh);
end

summaryTable = struct2table(summaryRows);
summaryPath = fullfile(resultsDir, "demo_simulation_results.csv");
writetable(summaryTable, summaryPath);

if writeMatlabFigures
    localExportModelImages(mdl, figuresDir);
end

fprintf("[run_demo_simulations] Saved demo summary -> %s\n", summaryPath);
if writeMatlabFigures
    fprintf("[run_demo_simulations] Exported model images and scenario plots -> %s\n", figuresDir);
else
    fprintf("[run_demo_simulations] Skipped MATLAB demo figures (Python manuscript figures use demo_timeseries_*.csv).\n");
end

%% Local functions
function in = localSetRecipeVariable(in, mdl, name, value)
in = in.setVariable(char(name), value, "Workspace", mdl);
end

function recipes = localDemoRecipes(P)
d = P.defaults;
recipes = [ ...
    localRecipe("baseline", d.T_C, d.Q_m3h, d.t_pre, d.t_alk, d.t_int, d.t_final, ...
        d.NaOH_pct, d.soil0, d.heat_rec, d.water_rec, d.T_in_C); ...
    localRecipe("water_saving", 65, 1.15, 240, 950, 260, 330, ...
        1.5, 0.6, 0.30, 0.55, d.T_in_C); ...
    localRecipe("energy_saving", 55, 1.35, 330, 1050, 300, 420, ...
        1.6, 0.6, 0.65, 0.25, d.T_in_C); ...
    localRecipe("hygiene_priority", 78, 2.15, 450, 1450, 420, 620, ...
        2.1, 0.7, 0.20, 0.15, d.T_in_C); ...
    localRecipe("high_soil_stress", 75, 2.30, 520, 1650, 500, 720, ...
        2.2, 0.95, 0.25, 0.10, d.T_in_C); ...
    localRecipe("low_cod_policy", 62, 1.70, 260, 760, 260, 360, ...
        1.2, 0.35, 0.45, 0.35, d.T_in_C)];
end

function r = localRecipe(scenario, T_C, Q_m3h, t_pre, t_alk, t_int, t_final, ...
        NaOH_pct, soil0, heat_rec, water_rec, T_in_C)
r = struct( ...
    "scenario", scenario, ...
    "T_C", T_C, ...
    "Q_m3h", Q_m3h, ...
    "t_pre", t_pre, ...
    "t_alk", t_alk, ...
    "t_int", t_int, ...
    "t_final", t_final, ...
    "NaOH_pct", NaOH_pct, ...
    "soil0", soil0, ...
    "heat_rec", heat_rec, ...
    "water_rec", water_rec, ...
    "T_in_C", T_in_C);
end

function r = localEmptySummary()
r = struct( ...
    "scenario", "", ...
    "T_C", NaN, ...
    "Q_m3h", NaN, ...
    "t_pre", NaN, ...
    "t_alk", NaN, ...
    "t_int", NaN, ...
    "t_final", NaN, ...
    "NaOH_pct", NaN, ...
    "soil0", NaN, ...
    "heat_rec", NaN, ...
    "water_rec", NaN, ...
    "T_in_C", NaN, ...
    "stopTime", NaN, ...
    "water_L", NaN, ...
    "thermal_energy_kWh", NaN, ...
    "pump_energy_kWh", NaN, ...
    "total_energy_kWh", NaN, ...
    "COD_mgL", NaN, ...
    "NaOH_residual_mgL", NaN, ...
    "COD_chem_equiv_mgL", NaN, ...
    "CO2eq_kg", NaN, ...
    "cleaning_score", NaN, ...
    "hygienic_risk", NaN, ...
    "EHPI", NaN, ...
    "solver_status", "success", ...
    "data_label", "simulation-generated synthetic data - NOT real measurements");
end

function row = localSummaryRow(recipe, stopTime, lo, P)
row = localEmptySummary();
fields = ["scenario", "T_C", "Q_m3h", "t_pre", "t_alk", "t_int", "t_final", ...
    "NaOH_pct", "soil0", "heat_rec", "water_rec", "T_in_C"];
for idx = 1:numel(fields)
    row.(fields(idx)) = recipe.(fields(idx));
end
row.stopTime = stopTime;
row.water_L = localFinal(lo, "water_L");
row.thermal_energy_kWh = localFinal(lo, "thermal_energy_kWh");
row.pump_energy_kWh = localFinal(lo, "pump_energy_kWh");
row.total_energy_kWh = row.thermal_energy_kWh + row.pump_energy_kWh;
row.COD_mgL = localFinal(lo, "COD_mgL");
row.NaOH_residual_mgL = localFinal(lo, "NaOH_residual_mgL");
row.COD_chem_equiv_mgL = P.COD_chemical_factor * row.NaOH_residual_mgL;
row.CO2eq_kg = localFinal(lo, "CO2eq_kg");
row.cleaning_score = localFinal(lo, "cleaning_score");
row.hygienic_risk = localFinal(lo, "hygienic_risk");
row.EHPI = localFinal(lo, "EHPI");
end

function v = localFinal(lo, name)
sig = lo.getElement(char(name)).Values;
data = double(squeeze(sig.Data));
v = data(end);
end

function localAssertLogsout(lo, expectedNames)
actual = string(lo.getElementNames());
missing = setdiff(string(expectedNames), actual);
if ~isempty(missing)
    error("run_demo_simulations:missingLogsout", ...
        "logsout is missing expected signals: %s", strjoin(missing, ", "));
end
end

function T = localTimeseriesTable(lo)
names = ["phase_id", "soil", "water_L", "thermal_energy_kWh", "pump_energy_kWh", ...
    "COD_mgL", "NaOH_residual_mgL", "CO2eq_kg", "cleaning_score", ...
    "hygienic_risk", "EHPI"];
base = lo.getElement("soil").Values;
time_s = double(base.Time(:));
T = table(time_s);
for idx = 1:numel(names)
    sig = lo.getElement(char(names(idx))).Values;
    method = "linear";
    if names(idx) == "phase_id"
        method = "previous";
    end
    T.(names(idx)) = localResample(sig, time_s, method);
end
T.total_energy_kWh = T.thermal_energy_kWh + T.pump_energy_kWh;
end

function values = localResample(sig, targetTime, method)
sourceTime = double(sig.Time(:));
sourceData = double(squeeze(sig.Data));
sourceData = sourceData(:);
[sourceTime, idx] = unique(sourceTime, "stable");
sourceData = sourceData(idx);
if isscalar(sourceTime)
    values = repmat(sourceData(1), size(targetTime));
    return;
end
values = interp1(sourceTime, sourceData, targetTime, char(method), "extrap");
end

function localPlotScenario(T, scenario, figuresDir)
scenarioId = localFileId(scenario);
fig = figure("Visible", "off", "Position", [100 100 1100 1200]);
tiledlayout(6, 1, "TileSpacing", "compact", "Padding", "compact");

nexttile;
stairs(T.time_s, T.phase_id, "LineWidth", 1.1);
grid on;
ylabel("phase_id");
title("Demo recipe: " + scenario + " (synthetic)");

nexttile;
plot(T.time_s, T.soil, "LineWidth", 1.1);
grid on;
ylabel("soil");

nexttile;
plot(T.time_s, T.water_L, "LineWidth", 1.1);
grid on;
ylabel("water L");

nexttile;
plot(T.time_s, T.COD_mgL, "LineWidth", 1.1);
grid on;
ylabel("COD mg/L");

nexttile;
plot(T.time_s, T.total_energy_kWh, "LineWidth", 1.1);
grid on;
ylabel("energy kWh");

nexttile;
plot(T.time_s, T.cleaning_score, "LineWidth", 1.1);
grid on;
ylabel("cleaning %");
xlabel("time (s)");

exportgraphics(fig, fullfile(figuresDir, "demo_" + scenarioId + "_timeseries.png"), "Resolution", 180);
close(fig);
end

function localExportModelImages(mdl, figuresDir)
systems = [mdl, ...
    mdl + "/Scenario Inputs", ...
    mdl + "/Phase Scheduler", ...
    mdl + "/Soil Removal Kinetics", ...
    mdl + "/Water Consumption", ...
    mdl + "/Thermal Energy", ...
    mdl + "/Pump Energy", ...
    mdl + "/Wastewater and COD", ...
    mdl + "/Hygiene and Risk", ...
    mdl + "/EHPI and Output Metrics", ...
    mdl + "/Logging and Scopes"];
files = ["simulink_top_level.png", ...
    "simulink_subsystem_scenario_inputs.png", ...
    "simulink_subsystem_phase_scheduler.png", ...
    "simulink_subsystem_soil_removal_kinetics.png", ...
    "simulink_subsystem_water_consumption.png", ...
    "simulink_subsystem_thermal_energy.png", ...
    "simulink_subsystem_pump_energy.png", ...
    "simulink_subsystem_wastewater_and_cod.png", ...
    "simulink_subsystem_hygiene_and_risk.png", ...
    "simulink_subsystem_ehpi_and_output_metrics.png", ...
    "simulink_subsystem_logging_and_scopes.png"];

for idx = 1:numel(systems)
    sys = systems(idx);
    outPath = fullfile(figuresDir, files(idx));
    open_system(sys);
    try
        set_param(sys, "ZoomFactor", "FitSystem");
    catch
    end
    print("-s" + sys, "-dpng", "-r180", outPath);
end
end

function id = localFileId(name)
id = lower(regexprep(string(name), "[^a-zA-Z0-9]+", "_"));
id = regexprep(id, "^_+|_+$", "");
end

function v = localEnvBool(name, default)
%LOCALENVBOOL Return a logical from an env var ('true'/'1' -> true, 'false'/'0' -> false).
v = default;
s = lower(strtrim(getenv(char(name))));
if strcmp(s, 'true') || strcmp(s, '1')
    v = true;
elseif strcmp(s, 'false') || strcmp(s, '0')
    v = false;
end
end
