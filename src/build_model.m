% Author: Ketney Otto
% Affiliation: "Lucian Blaga" University of Sibiu, Department of Agricultural
%              Science and Food Engineering, Dr. I. Ratiu Street, no. 7-9,
%              550012 Sibiu, Romania
% Contact: otto.ketney@ulbsibiu.ro | orcid.org/0000-0003-1638-1154

function build_model()
%BUILD_MODEL Programmatically construct the visual dairy CIP Simulink twin.
%
%   The generated model is a proof-of-concept, inspectable Simulink artifact
%   with top-level subsystems for scenario inputs, phase scheduling, kinetics,
%   water, energy, wastewater, hygiene, output metrics, and logging.
%
%   All generated results are SIMULATION-GENERATED SYNTHETIC DATA. Coefficients
%   are uncalibrated proof-of-concept assumptions and are not suitable for
%   operational control.
%
%   Scenario variables are injected by Simulink.SimulationInput.setVariable into
%   the model workspace. This script never writes scenario state to the base
%   workspace.
%
%   See also CIP_PARAMETERS, CIP_MODEL_PARAMS, RUN_CIP_SCENARIOS.

here = fileparts(mfilename("fullpath"));
root = fileparts(here);
addpath(here);

P = cip_parameters();
mdl = P.model_name;
modelDir = fullfile(root, "model");
mdlPath = fullfile(modelDir, mdl + ".slx");
if ~exist(modelDir, "dir")
    mkdir(modelDir);
end

if bdIsLoaded(mdl)
    close_system(mdl, 0);
end

% Suppress shadowing warning as we are programmatically rebuilding the model from scratch
oldWarn = warning('off', 'Simulink:Engine:MdlFileShadowing');
cleanupWarn = onCleanup(@() warning(oldWarn));

new_system(mdl, "Model");
load_system(mdl);

seedModelWorkspace(mdl, P);
configureModelCallbacks(mdl);

%% Top-level visual architecture
addBlock("simulink/Sources/Clock", mdl + "/Clock", [40 350 70 380]);

subsystems = struct( ...
    "scenario", "Scenario Inputs", ...
    "phase", "Phase Scheduler", ...
    "soil", "Soil Removal Kinetics", ...
    "water", "Water Consumption", ...
    "thermal", "Thermal Energy", ...
    "pump", "Pump Energy", ...
    "waste", "Wastewater and COD", ...
    "hygiene", "Hygiene and Risk", ...
    "metrics", "EHPI and Output Metrics", ...
    "logging", "Logging and Scopes");

createSubsystem(mdl, subsystems.scenario, [120 65 280 655]);
createSubsystem(mdl, subsystems.phase, [350 70 535 205]);
createSubsystem(mdl, subsystems.soil, [610 75 835 210]);
createSubsystem(mdl, subsystems.water, [610 245 835 360]);
createSubsystem(mdl, subsystems.thermal, [610 400 835 520]);
createSubsystem(mdl, subsystems.pump, [610 560 835 675]);
createSubsystem(mdl, subsystems.waste, [910 90 1145 240]);
createSubsystem(mdl, subsystems.hygiene, [910 310 1145 430]);
createSubsystem(mdl, subsystems.metrics, [1215 285 1465 455]);
createSubsystem(mdl, subsystems.logging, [1535 85 1725 610]);

addSyntheticDisclaimer(mdl);

populateScenarioInputs(mdl + "/" + subsystems.scenario);
populatePhaseScheduler(mdl + "/" + subsystems.phase);
populateSoilKinetics(mdl + "/" + subsystems.soil);
populateWaterConsumption(mdl + "/" + subsystems.water);
populateThermalEnergy(mdl + "/" + subsystems.thermal);
populatePumpEnergy(mdl + "/" + subsystems.pump);
populateWastewaterCod(mdl + "/" + subsystems.waste);
populateHygieneRisk(mdl + "/" + subsystems.hygiene);
populateOutputMetrics(mdl + "/" + subsystems.metrics);
populateLoggingScopes(mdl + "/" + subsystems.logging);

%% Top-level wiring
s = subsystems.scenario;
p = subsystems.phase;
sk = subsystems.soil;
w = subsystems.water;
th = subsystems.thermal;
pu = subsystems.pump;
ww = subsystems.waste;
hy = subsystems.hygiene;
om = subsystems.metrics;
lg = subsystems.logging;

% Scenario Inputs output order:
% 1 T_C, 2 Q_m3h, 3 t_pre, 4 t_alk, 5 t_int, 6 t_final, 7 NaOH_pct,
% 8 soil0, 9 heat_rec, 10 water_rec, 11 T_in_C.
wire(mdl, "Clock/1", p + "/1");
wire(mdl, s + "/3", p + "/2");
wire(mdl, s + "/4", p + "/3");
wire(mdl, s + "/5", p + "/4");
wire(mdl, s + "/6", p + "/5");

wire(mdl, p + "/1", sk + "/1");
wire(mdl, s + "/8", sk + "/2");
wire(mdl, s + "/1", sk + "/3");
wire(mdl, s + "/2", sk + "/4");
wire(mdl, s + "/7", sk + "/5");

wire(mdl, p + "/1", w + "/1");
wire(mdl, s + "/2", w + "/2");
wire(mdl, s + "/10", w + "/3");

wire(mdl, p + "/1", th + "/1");
wire(mdl, s + "/1", th + "/2");
wire(mdl, s + "/2", th + "/3");
wire(mdl, s + "/9", th + "/4");
wire(mdl, s + "/11", th + "/5");

wire(mdl, p + "/1", pu + "/1");
wire(mdl, s + "/2", pu + "/2");

wire(mdl, "Clock/1", ww + "/1");
wire(mdl, p + "/1", ww + "/2");
wire(mdl, sk + "/2", ww + "/3");
wire(mdl, s + "/7", ww + "/4");

wire(mdl, sk + "/1", hy + "/1");

wire(mdl, w + "/1", om + "/1");
wire(mdl, th + "/1", om + "/2");
wire(mdl, pu + "/1", om + "/3");
wire(mdl, ww + "/1", om + "/4");
wire(mdl, hy + "/1", om + "/5");

wire(mdl, p + "/1", lg + "/1");
wire(mdl, sk + "/1", lg + "/2");
wire(mdl, w + "/1", lg + "/3");
wire(mdl, th + "/1", lg + "/4");
wire(mdl, pu + "/1", lg + "/5");
wire(mdl, ww + "/1", lg + "/6");
wire(mdl, ww + "/2", lg + "/7");
wire(mdl, om + "/2", lg + "/8");
wire(mdl, hy + "/1", lg + "/9");
wire(mdl, hy + "/2", lg + "/10");
wire(mdl, om + "/3", lg + "/11");

%% Signal logging contract
logSig(mdl, subsystems.soil, 1, "soil");
logSig(mdl, subsystems.water, 1, "water_L");
logSig(mdl, subsystems.thermal, 1, "thermal_energy_kWh");
logSig(mdl, subsystems.pump, 1, "pump_energy_kWh");
logSig(mdl, subsystems.waste, 1, "COD_mgL");
logSig(mdl, subsystems.waste, 2, "NaOH_residual_mgL");
logSig(mdl, subsystems.metrics, 2, "CO2eq_kg");
logSig(mdl, subsystems.hygiene, 1, "cleaning_score");
logSig(mdl, subsystems.hygiene, 2, "hygienic_risk");
logSig(mdl, subsystems.metrics, 3, "EHPI");
logSig(mdl, subsystems.phase, 1, "phase_id");

%% Model configuration
set_param(mdl, "SignalLogging", "on", "SignalLoggingName", "logsout");
set_param(mdl, "SaveOutput", "off", "SaveTime", "off", "ReturnWorkspaceOutputs", "on");
set_param(mdl, "SolverType", "Variable-step", "Solver", P.solver);
set_param(mdl, "StopTime", "1900");
set_param(mdl, "MaxStep", num2str(P.max_step_cap));
set_param(mdl, "RelTol", "1e-4");

save_system(mdl, mdlPath);
fprintf("[build_model] Saved visual synthetic CIP model -> %s\n", mdlPath);
close_system(mdl, 0);
end

%% Block population
function populateScenarioInputs(subPath)
names = ["T_C", "Q_m3h", "t_pre", "t_alk", "t_int", "t_final", ...
    "NaOH_pct", "soil0", "heat_rec", "water_rec", "T_in_C"];
for idx = 1:numel(names)
    y = 35 + (idx - 1)*48;
    cName = "Const_" + names(idx);
    addBlock("simulink/Sources/Constant", subPath + "/" + cName, [35 y 150 y+28]);
    set_param(subPath + "/" + cName, "Value", names(idx));
    addOutport(subPath, names(idx), [235 y 265 y+28]);
    wire(subPath, cName + "/1", names(idx) + "/1");
end
end

function populatePhaseScheduler(subPath)
addInport(subPath, "t", [35 45 65 59]);
addInport(subPath, "t_pre", [35 85 65 99]);
addInport(subPath, "t_alk", [35 125 65 139]);
addInport(subPath, "t_int", [35 165 65 179]);
addInport(subPath, "t_final", [35 205 65 219]);
addOutport(subPath, "phase_id", [430 120 460 134]);

chartPath = subPath + "/Stateflow Scheduler";
try
    buildStateflowScheduler(chartPath, [150 60 315 210]);
    wire(subPath, "t/1", "Stateflow Scheduler/1");
    wire(subPath, "t_pre/1", "Stateflow Scheduler/2");
    wire(subPath, "t_alk/1", "Stateflow Scheduler/3");
    wire(subPath, "t_int/1", "Stateflow Scheduler/4");
    wire(subPath, "t_final/1", "Stateflow Scheduler/5");
    wire(subPath, "Stateflow Scheduler/1", "phase_id/1");
catch ME
    warning("build_model:stateflowFallback", ...
        "Stateflow scheduler unavailable (%s). Using MATLAB Function scheduler.", ME.message);
    if blockExists(chartPath)
        delete_block(chartPath);
    end
    addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Phase Logic", [150 70 315 200]);
    setFcn(subPath + "/Phase Logic", phaseSchedulerScript());
    wire(subPath, "t/1", "Phase Logic/1");
    wire(subPath, "t_pre/1", "Phase Logic/2");
    wire(subPath, "t_alk/1", "Phase Logic/3");
    wire(subPath, "t_int/1", "Phase Logic/4");
    wire(subPath, "t_final/1", "Phase Logic/5");
    wire(subPath, "Phase Logic/1", "phase_id/1");
end
end

function populateSoilKinetics(subPath)
addInport(subPath, "phase_id", [30 55 60 69]);
addInport(subPath, "soil0", [30 105 60 119]);
addInport(subPath, "T_C", [30 155 60 169]);
addInport(subPath, "Q_m3h", [30 205 60 219]);
addInport(subPath, "NaOH_pct", [30 255 60 269]);
addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Kinetics", [150 75 320 255]);
addBlock("simulink/Continuous/Integrator", subPath + "/Soil State", [400 88 430 122]);
set_param(subPath + "/Soil State", "InitialCondition", "soil0");
addOutport(subPath, "soil", [520 90 550 104]);
addOutport(subPath, "soil_removed_cum", [520 145 550 159]);
addOutport(subPath, "soil_removed_rate", [520 200 550 214]);
setFcn(subPath + "/Kinetics", soilKineticsScript());

wire(subPath, "phase_id/1", "Kinetics/1");
wire(subPath, "Soil State/1", "Kinetics/2");
wire(subPath, "soil0/1", "Kinetics/3");
wire(subPath, "T_C/1", "Kinetics/4");
wire(subPath, "Q_m3h/1", "Kinetics/5");
wire(subPath, "NaOH_pct/1", "Kinetics/6");
wire(subPath, "Kinetics/1", "Soil State/1");
wire(subPath, "Soil State/1", "soil/1");
wire(subPath, "Kinetics/3", "soil_removed_cum/1");
wire(subPath, "Kinetics/2", "soil_removed_rate/1");
end

function populateWaterConsumption(subPath)
addInport(subPath, "phase_id", [35 50 65 64]);
addInport(subPath, "Q_m3h", [35 100 65 114]);
addInport(subPath, "water_rec", [35 150 65 164]);
addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Water Rate", [150 70 305 155]);
addBlock("simulink/Continuous/Integrator", subPath + "/Water Integrator", [375 90 405 124]);
set_param(subPath + "/Water Integrator", "InitialCondition", "0");
addOutport(subPath, "water_L", [500 95 530 109]);
setFcn(subPath + "/Water Rate", waterRateScript());

wire(subPath, "phase_id/1", "Water Rate/1");
wire(subPath, "Q_m3h/1", "Water Rate/2");
wire(subPath, "water_rec/1", "Water Rate/3");
wire(subPath, "Water Rate/1", "Water Integrator/1");
wire(subPath, "Water Integrator/1", "water_L/1");
end

function populateThermalEnergy(subPath)
addInport(subPath, "phase_id", [30 45 60 59]);
addInport(subPath, "T_C", [30 90 60 104]);
addInport(subPath, "Q_m3h", [30 135 60 149]);
addInport(subPath, "heat_rec", [30 180 60 194]);
addInport(subPath, "T_in_C", [30 225 60 239]);
addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Thermal Power", [145 70 315 205]);
addBlock("simulink/Continuous/Integrator", subPath + "/Thermal kW s", [380 115 410 149]);
addBlock("simulink/Math Operations/Gain", subPath + "/Seconds to kWh", [465 115 515 149]);
set_param(subPath + "/Thermal kW s", "InitialCondition", "0");
set_param(subPath + "/Seconds to kWh", "Gain", "1/3600");
addOutport(subPath, "thermal_energy_kWh", [585 120 615 134]);
setFcn(subPath + "/Thermal Power", thermalPowerScript());

wire(subPath, "phase_id/1", "Thermal Power/1");
wire(subPath, "T_C/1", "Thermal Power/2");
wire(subPath, "Q_m3h/1", "Thermal Power/3");
wire(subPath, "heat_rec/1", "Thermal Power/4");
wire(subPath, "T_in_C/1", "Thermal Power/5");
wire(subPath, "Thermal Power/1", "Thermal kW s/1");
wire(subPath, "Thermal kW s/1", "Seconds to kWh/1");
wire(subPath, "Seconds to kWh/1", "thermal_energy_kWh/1");
end

function populatePumpEnergy(subPath)
addInport(subPath, "phase_id", [35 55 65 69]);
addInport(subPath, "Q_m3h", [35 115 65 129]);
addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Pump Power", [150 65 305 140]);
addBlock("simulink/Continuous/Integrator", subPath + "/Pump kW s", [375 78 405 112]);
addBlock("simulink/Math Operations/Gain", subPath + "/Seconds to kWh", [465 78 515 112]);
set_param(subPath + "/Pump kW s", "InitialCondition", "0");
set_param(subPath + "/Seconds to kWh", "Gain", "1/3600");
addOutport(subPath, "pump_energy_kWh", [585 85 615 99]);
setFcn(subPath + "/Pump Power", pumpPowerScript());

wire(subPath, "phase_id/1", "Pump Power/1");
wire(subPath, "Q_m3h/1", "Pump Power/2");
wire(subPath, "Pump Power/1", "Pump kW s/1");
wire(subPath, "Pump kW s/1", "Seconds to kWh/1");
wire(subPath, "Seconds to kWh/1", "pump_energy_kWh/1");
end

function populateWastewaterCod(subPath)
addInport(subPath, "t", [30 45 60 59]);
addInport(subPath, "phase_id", [30 90 60 104]);
addInport(subPath, "soil_removed_cum", [30 135 60 149]);
addInport(subPath, "NaOH_pct", [30 180 60 194]);
addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Organic COD and NaOH", [155 70 365 200]);
addBlock("simulink/Continuous/Integrator", subPath + "/NaOH Integral", [430 122 460 156]);
set_param(subPath + "/NaOH Integral", "InitialCondition", "0");
addOutport(subPath, "COD_mgL", [570 82 600 96]);
addOutport(subPath, "NaOH_residual_mgL", [570 145 600 159]);
setFcn(subPath + "/Organic COD and NaOH", wastewaterCodScript());

wire(subPath, "t/1", "Organic COD and NaOH/1");
wire(subPath, "phase_id/1", "Organic COD and NaOH/2");
wire(subPath, "soil_removed_cum/1", "Organic COD and NaOH/3");
wire(subPath, "NaOH_pct/1", "Organic COD and NaOH/4");
wire(subPath, "NaOH Integral/1", "Organic COD and NaOH/5");
wire(subPath, "Organic COD and NaOH/1", "COD_mgL/1");
wire(subPath, "Organic COD and NaOH/2", "NaOH Integral/1");
wire(subPath, "Organic COD and NaOH/3", "NaOH_residual_mgL/1");
end

function populateHygieneRisk(subPath)
addInport(subPath, "soil", [35 85 65 99]);
addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Hygiene Proxy", [150 60 325 135]);
addOutport(subPath, "cleaning_score", [430 70 460 84]);
addOutport(subPath, "hygienic_risk", [430 120 460 134]);
setFcn(subPath + "/Hygiene Proxy", hygieneRiskScript());
wire(subPath, "soil/1", "Hygiene Proxy/1");
wire(subPath, "Hygiene Proxy/1", "cleaning_score/1");
wire(subPath, "Hygiene Proxy/2", "hygienic_risk/1");
end

function populateOutputMetrics(subPath)
addInport(subPath, "water_L", [30 45 60 59]);
addInport(subPath, "thermal_energy_kWh", [30 90 60 104]);
addInport(subPath, "pump_energy_kWh", [30 135 60 149]);
addInport(subPath, "COD_mgL", [30 180 60 194]);
addInport(subPath, "cleaning_score", [30 225 60 239]);
addBlock("simulink/User-Defined Functions/MATLAB Function", subPath + "/Output Metrics", [160 80 350 210]);
addOutport(subPath, "total_energy_kWh", [460 90 490 104]);
addOutport(subPath, "CO2eq_kg", [460 145 490 159]);
addOutport(subPath, "EHPI", [460 200 490 214]);
setFcn(subPath + "/Output Metrics", outputMetricsScript());

wire(subPath, "water_L/1", "Output Metrics/1");
wire(subPath, "thermal_energy_kWh/1", "Output Metrics/2");
wire(subPath, "pump_energy_kWh/1", "Output Metrics/3");
wire(subPath, "COD_mgL/1", "Output Metrics/4");
wire(subPath, "cleaning_score/1", "Output Metrics/5");
wire(subPath, "Output Metrics/1", "total_energy_kWh/1");
wire(subPath, "Output Metrics/2", "CO2eq_kg/1");
wire(subPath, "Output Metrics/3", "EHPI/1");
end

function populateLoggingScopes(subPath)
names = ["phase_id", "soil", "water_L", "thermal_energy_kWh", "pump_energy_kWh", ...
    "COD_mgL", "NaOH_residual_mgL", "CO2eq_kg", "cleaning_score", ...
    "hygienic_risk", "EHPI"];
for idx = 1:numel(names)
    y = 30 + (idx - 1)*38;
    addInport(subPath, names(idx), [35 y 65 y+14]);
end
addBlock("simulink/Signal Routing/Mux", subPath + "/Process Trace Mux", [175 35 180 235]);
set_param(subPath + "/Process Trace Mux", "Inputs", "6");
addBlock("simulink/Sinks/Scope", subPath + "/Process Trace Scope", [255 90 310 145]);
wire(subPath, "phase_id/1", "Process Trace Mux/1");
wire(subPath, "soil/1", "Process Trace Mux/2");
wire(subPath, "water_L/1", "Process Trace Mux/3");
wire(subPath, "COD_mgL/1", "Process Trace Mux/4");
wire(subPath, "thermal_energy_kWh/1", "Process Trace Mux/5");
wire(subPath, "cleaning_score/1", "Process Trace Mux/6");
wire(subPath, "Process Trace Mux/1", "Process Trace Scope/1");

for idx = 1:numel(names)
    if ismember(names(idx), ["phase_id", "soil", "water_L", "COD_mgL", ...
            "thermal_energy_kWh", "cleaning_score"])
        continue;
    end
    y = 30 + (idx - 1)*38;
    tName = "Term_" + names(idx);
    addBlock("simulink/Sinks/Terminator", subPath + "/" + tName, [420 y 440 y+18]);
    wire(subPath, names(idx) + "/1", tName + "/1");
end
end

%% Embedded MATLAB Function scripts
function s = phaseSchedulerScript()
L = {
"function phase_id = phase_logic(t, t_pre, t_alk, t_int, t_final) %#codegen"
"%PHASE_LOGIC Time-driven fallback phase scheduler."
"if t <= t_pre"
"    phase_id = 1;"
"elseif t <= t_pre + t_alk"
"    phase_id = 2;"
"elseif t <= t_pre + t_alk + t_int"
"    phase_id = 3;"
"elseif t <= t_pre + t_alk + t_int + t_final"
"    phase_id = 4;"
"else"
"    phase_id = 5;"
"end"
"end"
};
s = joinLines(L);
end

function s = soilKineticsScript()
L = {
"function [dsoil_dt, soil_removed_rate, soil_removed_cum] = kinetics(phase_id, soil, soil0, T_C, Q_m3h, NaOH_pct) %#codegen"
"%KINETICS First-order soil removal for synthetic dairy CIP."
"M = cip_model_params();"
"soil_c = max(soil, 0);"
"if phase_id == 1"
"    k = M.k_cal * M.k_pre_base * (Q_m3h / M.Q_ref)^M.beta_Q;"
"elseif phase_id == 2"
"    k = M.k_cal * M.k_alk_base * exp(M.alpha_T*(T_C - M.T_ref)) * ..."
"        (Q_m3h / M.Q_ref)^M.beta_Q * (NaOH_pct / M.NaOH_ref)^M.gamma_NaOH;"
"elseif phase_id == 3 || phase_id == 4"
"    k = M.k_cal * M.k_rinse_base * (Q_m3h / M.Q_ref)^M.beta_Q;"
"else"
"    k = 0;"
"end"
"dsoil_dt = -k * soil_c;"
"soil_removed_rate = max(-dsoil_dt, 0);"
"soil_removed_cum = min(max(soil0 - soil_c, 0), max(soil0, 0));"
"end"
};
s = joinLines(L);
end

function s = waterRateScript()
L = {
"function water_L_s = water_rate(phase_id, Q_m3h, water_rec) %#codegen"
"%WATER_RATE Fresh-water flow during active CIP phases."
"if phase_id >= 1 && phase_id <= 4"
"    water_L_s = Q_m3h * 1000 / 3600 * (1 - water_rec);"
"else"
"    water_L_s = 0;"
"end"
"end"
};
s = joinLines(L);
end

function s = thermalPowerScript()
L = {
"function thermal_kW = thermal_power(phase_id, T_C, Q_m3h, heat_rec, T_in_C) %#codegen"
"%THERMAL_POWER Heating power for the alkaline wash phase."
"M = cip_model_params();"
"if phase_id == 2"
"    Q_m3s = Q_m3h / 3600;"
"    m_dot = M.rho * Q_m3s;"
"    dTemp = max(T_C - T_in_C, 0);"
"    thermal_kW = m_dot * M.cp * dTemp / M.eta_heater * (1 - heat_rec);"
"else"
"    thermal_kW = 0;"
"end"
"end"
};
s = joinLines(L);
end

function s = pumpPowerScript()
L = {
"function pump_kW = pump_power(phase_id, Q_m3h) %#codegen"
"%PUMP_POWER Pumping power during active CIP phases."
"M = cip_model_params();"
"if phase_id >= 1 && phase_id <= 4"
"    Q_m3s = Q_m3h / 3600;"
"    pump_kW = (M.deltaP * Q_m3s / M.eta_pump) / 1000;"
"else"
"    pump_kW = 0;"
"end"
"end"
};
s = joinLines(L);
end

function s = wastewaterCodScript()
L = {
"function [COD_mgL, NaOH_res, NaOH_residual_mgL] = wastewater_cod(t, phase_id, soil_removed_cum, NaOH_pct, NaOH_integral) %#codegen"
"%WASTEWATER_COD Organic COD proxy and separate NaOH residual reporting."
"M = cip_model_params();"
"COD_mgL = M.COD_factor * max(soil_removed_cum, 0);"
"if phase_id == 2"
"    NaOH_res = NaOH_pct * 10000;"
"elseif phase_id == 3"
"    NaOH_res = NaOH_pct * 1500;"
"elseif phase_id == 4"
"    NaOH_res = NaOH_pct * 300;"
"else"
"    NaOH_res = 0;"
"end"
"NaOH_residual_mgL = NaOH_integral / max(t, M.eps_time);"
"end"
};
s = joinLines(L);
end

function s = hygieneRiskScript()
L = {
"function [cleaning_score, hygienic_risk] = hygiene_proxy(soil) %#codegen"
"%HYGIENE_PROXY Residual-soil hygiene proxies for synthetic data."
"M = cip_model_params();"
"soil_c = max(soil, 0);"
"cleaning_score = max(0, min(100, (1 - soil_c) * 100));"
"hygienic_risk = max(0, min(1, soil_c / M.soil_risk_ref));"
"end"
};
s = joinLines(L);
end

function s = outputMetricsScript()
L = {
"function [total_energy_kWh, CO2eq_kg, EHPI] = output_metrics(water_L, thermal_energy_kWh, pump_energy_kWh, COD_mgL, cleaning_score) %#codegen"
"%OUTPUT_METRICS Derived synthetic environmental and hygiene metrics."
"M = cip_model_params();"
"total_energy_kWh = thermal_energy_kWh + pump_energy_kWh;"
"CO2eq_kg = thermal_energy_kWh * M.EF_thermal + pump_energy_kWh * M.EF_electricity;"
"water_norm = water_L / M.norm_water_L;"
"energy_norm = total_energy_kWh / M.norm_energy_kWh;"
"COD_norm = COD_mgL / M.norm_COD_mgL;"
"CO2_norm = CO2eq_kg / M.norm_CO2eq_kg;"
"cleaning_norm = cleaning_score / 100;"
"penalty_env = 0.25*water_norm + 0.25*energy_norm + 0.25*COD_norm + 0.25*CO2_norm;"
"EHPI = 100 * cleaning_norm / (1 + penalty_env);"
"end"
};
s = joinLines(L);
end

%% Stateflow scheduler
function buildStateflowScheduler(chartPath, pos)
addBlock("sflib/Chart", chartPath, pos);
rt = sfroot;
chs = rt.find("-isa", "Stateflow.Chart", "Path", chartPath);
if isempty(chs)
    error("build_model:noStateflowChart", "Could not access chart %s.", chartPath);
end
ch = chs(1);
ch.ActionLanguage = "MATLAB";

addChartData(ch, "t", "Input", 1);
addChartData(ch, "t_pre", "Input", 2);
addChartData(ch, "t_alk", "Input", 3);
addChartData(ch, "t_int", "Input", 4);
addChartData(ch, "t_final", "Input", 5);
addChartData(ch, "phase_id", "Output", 1);

sPre = addState(ch, "PRE_RINSE" + newline + "entry: phase_id = 1;", [35 30 150 50]);
sAlk = addState(ch, "ALKALINE_WASH" + newline + "entry: phase_id = 2;", [35 120 165 50]);
sInt = addState(ch, "INTERMEDIATE_RINSE" + newline + "entry: phase_id = 3;", [35 210 190 50]);
sFin = addState(ch, "FINAL_RINSE" + newline + "entry: phase_id = 4;", [35 300 150 50]);
sEnd = addState(ch, "ENDING" + newline + "entry: phase_id = 5;", [35 390 150 50]);

dt = Stateflow.Transition(ch);
dt.Destination = sPre;
dt.DestinationOClock = 0;
dt.SourceEndPoint = [sPre.Position(1)+40, sPre.Position(2)-25];
dt.MidPoint = [sPre.Position(1)+40, sPre.Position(2)-12];

addTransition(ch, sPre, sAlk, "[t > t_pre]");
addTransition(ch, sAlk, sInt, "[t > t_pre + t_alk]");
addTransition(ch, sInt, sFin, "[t > t_pre + t_alk + t_int]");
addTransition(ch, sFin, sEnd, "[t > t_pre + t_alk + t_int + t_final]");

try
    set_param(chartPath, "SampleTime", "1");
catch
end
end

function addChartData(ch, name, scope, port)
d = Stateflow.Data(ch);
d.Name = name;
d.Scope = scope;
try
    d.Port = port;
catch
end
end

function s = addState(ch, label, pos)
s = Stateflow.State(ch);
s.LabelString = label;
s.Position = pos;
end

function t = addTransition(ch, src, dst, label)
t = Stateflow.Transition(ch);
t.Source = src;
t.Destination = dst;
t.LabelString = label;
end

%% Simulink helpers
function createSubsystem(mdl, name, pos)
subPath = mdl + "/" + name;
addBlock("simulink/Ports & Subsystems/Subsystem", subPath, pos);
deleteContents(subPath);
end

function deleteContents(subPath)
lines = find_system(subPath, "FindAll", "on", "SearchDepth", 1, "Type", "line");
for idx = 1:numel(lines)
    try
        delete_line(lines(idx));
    catch
    end
end
blocks = find_system(subPath, "SearchDepth", 1, "Type", "Block");
for idx = 1:numel(blocks)
    if strcmp(blocks{idx}, subPath)
        continue;
    end
    delete_block(blocks{idx});
end
end

function addInport(subPath, name, pos)
addBlock("simulink/Sources/In1", subPath + "/" + name, pos);
end

function addOutport(subPath, name, pos)
addBlock("simulink/Sinks/Out1", subPath + "/" + name, pos);
end

function addBlock(lib, dst, pos)
add_block(lib, dst, "Position", pos);
end

function wire(sys, srcSpec, dstSpec)
add_line(sys, srcSpec, dstSpec, "autorouting", "on");
end

function logSig(mdl, blk, port, name)
ph = get_param(mdl + "/" + blk, "PortHandles");
p = ph.Outport(port);
set_param(p, "DataLogging", "on");
set_param(p, "DataLoggingNameMode", "Custom");
set_param(p, "DataLoggingName", name);
end

function setFcn(blkPath, scriptText)
ok = false;
try
    cfg = get_param(blkPath, "MATLABFunctionConfiguration");
    cfg.FunctionScript = scriptText;
    ok = true;
catch
end
if ~ok
    rt = sfroot;
    chart = rt.find("-isa", "Stateflow.EMChart", "Path", blkPath);
    if isempty(chart)
        error("build_model:noMatlabFunction", "Could not configure %s.", blkPath);
    end
    chart(1).Script = scriptText;
end
end

function tf = bdIsLoaded(mdl)
tf = any(strcmp(find_system("SearchDepth", 0, "type", "block_diagram"), mdl));
end

function tf = blockExists(blockPath)
try
    get_param(blockPath, "Handle");
    tf = true;
catch
    tf = false;
end
end

function seedModelWorkspace(mdl, P)
mws = get_param(mdl, "ModelWorkspace");
names = fieldnames(P.defaults);
for idx = 1:numel(names)
    assignin(mws, names{idx}, P.defaults.(names{idx}));
end
end

function configureModelCallbacks(mdl)
pathSetup = modelPathSetupCallback(mdl);
set_param(mdl, "PostLoadFcn", pathSetup, "InitFcn", pathSetup);
end

function s = modelPathSetupCallback(mdl)
L = {
"try"
"    model_name = '" + mdl + "';"
"    model_file = get_param(model_name, 'FileName');"
"    if ~isempty(model_file)"
"        project_root = fileparts(fileparts(model_file));"
"    else"
"        project_root = pwd;"
"    end"
"    src_dir = fullfile(project_root, 'src');"
"    if ~isfolder(src_dir)"
"        src_dir = fullfile(pwd, 'src');"
"    end"
"    if isfolder(src_dir)"
"        addpath(src_dir);"
"    end"
"catch ME"
"    warning('dairy_cip_digital_twin:pathSetupFailed', ..."
"        'Could not add project src to MATLAB path: %s', ME.message);"
"end"
};
s = joinLines(L);
end

function addSyntheticDisclaimer(mdl)
try
    text = ["SIMULATION-GENERATED SYNTHETIC DATA ONLY", ...
        "Proof-of-concept model; uncalibrated and not for operational control."];
    note = Simulink.Annotation(mdl, strjoin(text, newline));
    note.Position = [95 20 560 55];
catch
end
end

function s = joinLines(lines)
s = strjoin(string(lines), newline);
end
