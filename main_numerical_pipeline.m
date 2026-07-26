function main_numerical_pipeline(repo_root)
% MAIN_NUMERICAL_PIPELINE.M  VsPredict_Geoenergy_v4 numerical core.
%
%  Called by run_pipeline.m (script) after path is cleaned.
%  Do not call directly — use:  run_pipeline
%
%  repo_root is passed explicitly from run_pipeline.m to avoid
%  any ambiguity from mfilename() depth inside package functions.

if nargin < 1 || isempty(repo_root)
    % Fallback: called directly, compute from mfilename
    repo_root = fileparts(mfilename('fullpath'));
    warning('main:directCall', ...
        'Call via run_pipeline.m for a clean path. repo_root=%s', repo_root);
end

fprintf('\n%s\n', repmat('=',1,65));
fprintf('  VsPredict_Geoenergy_v4 | Numerical Pipeline\n');
fprintf('  Geoenergy Science and Engineering (Elsevier Q1)\n');
fprintf('%s\n\n', repmat('=',1,65));

%% GATE 0: REPOSITORY AUDIT
audit_dir = fullfile(repo_root, 'audit');
if ~isfile(fullfile(audit_dir,'PROPOSED_REFACTOR_PLAN.md'))
    error('Pipeline:Gate0Fail','Gate 0 not complete. Run Phase 0 audit first.');
end
fprintf('[GATE_0] REPOSITORY_AUDIT = PASS (audit/ folder present)\n\n');

%% LOAD CONFIGURATION
cfg = config_geoenergy_v4();
cfg.compute.execution_environment = 'cpu';
cfg.compute.use_parallel = false;
cfg.compute.allow_gpu    = false;
cfg.training.shuffle     = 'never';
% Pass repo_root through config so all +core functions can access it
cfg.repo_root = repo_root;
fprintf('  [REPO] Root: %s\n', cfg.repo_root);

%% GATE 1: INITIALIZATION
fprintf('[PHASE 1] Run initialization...\n');
run = core.initialize_run(cfg);
assert(strcmp(run.gate.GATE_1_INITIALIZATION,'PASS'), 'Gate 1 failed.');
fprintf('[GATE_1] INITIALIZATION = PASS\n\n');

%% GATE 2: DATA LOADING AND OVERLAP AUDIT
fprintf('[PHASE 2] Data loading and overlap audit...\n');
run = core.load_well_data(run, cfg);
run = core.standardize_columns(run, cfg);
run = core.audit_overlap(run, cfg);
run = core.define_data_roles(run, cfg);
assert(strcmp(run.gate.GATE_2_DATA_AND_OVERLAP,'PASS'), ...
    'Gate 2 failed: %s', run.gate.GATE_2_DATA_AND_OVERLAP);
fprintf('[GATE_2] DATA_AND_OVERLAP = PASS\n\n');

%% GATE 3: PARTITIONING
fprintf('[PHASE 3] Data partitioning...\n');
run = core.build_depth_folds(run, cfg);
assert(strcmp(run.gate.GATE_3_PARTITION,'PASS'),'Gate 3 failed.');
fprintf('[GATE_3] PARTITION = PASS\n\n');

%% GATE 4: PREPROCESSING
fprintf('[PHASE 4] Fold-local preprocessing...\n');
run = core.fit_preprocessor(run, cfg);
run = core.apply_preprocessor(run, cfg);
assert(strcmp(run.gate.GATE_4_PREPROCESSING,'PASS'),'Gate 4 failed.');
fprintf('[GATE_4] PREPROCESSING = PASS\n\n');

%% GATE 5: FEATURE SELECTION
fprintf('[PHASE 5] Development-level feature analysis (diagnostic)...\n');
run = core.run_feature_selection(run, cfg);
check_gate(run.gate.GATE_5_FEATURE_SELECTION,'Gate 5');
fprintf('[GATE_5] FEATURE_ANALYSIS = %s\n\n', run.gate.GATE_5_FEATURE_SELECTION);

%% GATE 6: HYPERPARAMETER TUNING
fprintf('[PHASE 6] Hyperparameter optimization...\n');
run = core.tune_hyperparameters(run, cfg);
check_gate(run.gate.GATE_6_HYPERPARAMETER_TUNING,'Gate 6');
fprintf('[GATE_6] HYPERPARAMETER_TUNING = %s\n\n', run.gate.GATE_6_HYPERPARAMETER_TUNING);

%% GATE 7: OOF AND BASE MODELS
fprintf('[PHASE 7] OOF generation and base model training...\n');
run = core.generate_oof_predictions(run, cfg);
check_gate(run.gate.GATE_7_OOF_AND_BASE_MODELS,'Gate 7');
fprintf('[GATE_7] OOF_AND_BASE_MODELS = %s\n\n', run.gate.GATE_7_OOF_AND_BASE_MODELS);

%% GATE 8: META-LEARNERS
fprintf('[PHASE 8] Meta-learner training...\n');
run = core.build_meta_features(run, cfg);
run = core.train_meta_model(run, cfg);
run = core.select_model(run, cfg);
check_gate(run.gate.GATE_8_META_LEARNERS,'Gate 8');
fprintf('[GATE_8] META_LEARNERS = %s\n\n', run.gate.GATE_8_META_LEARNERS);

%% GATE 9: ABLATION
fprintf('[PHASE 9] Ablation study...\n');
run = core.run_ablation(run, cfg);
check_gate(run.gate.GATE_9_ABLATION,'Gate 9');
fprintf('[GATE_9] ABLATION = %s\n\n', run.gate.GATE_9_ABLATION);

%% LEVEL-2 MODEL SELECTION AUDIT (after ablation provides CV data)
fprintf('[AUDIT] Level-2 model selection and stacking value-added audit...\n');
try
    run = core.run_model_selection_audit(run, cfg);
catch ME_sel
    fprintf('[WARN] Model selection audit: %s\n', ME_sel.message);
end

%% GATE 11: FROZEN DEPLOYMENT (before multi-seed so pm_full exists)
% freeze_deployment writes PREPROCESSOR_FULL_WELLA.mat which run_multiseed needs.
fprintf('[PHASE 11] Frozen deployment...\n');
run = core.freeze_deployment(run, cfg);
check_gate(run.gate.GATE_11_FROZEN_DEPLOYMENT,'Gate 11');
fprintf('[GATE_11] FROZEN_DEPLOYMENT = %s\n\n', run.gate.GATE_11_FROZEN_DEPLOYMENT);

%% GATE 10: MULTI-SEED (after Gate 11 so PREPROCESSOR_FULL_WELLA.mat is available)
fprintf('[PHASE 10] Multi-seed robustness (%d seeds)...\n', numel(cfg.seeds.all));
run = core.run_multiseed(run, cfg);
check_gate(run.gate.GATE_10_MULTISEED,'Gate 10');
fprintf('[GATE_10] MULTISEED = %s\n\n', run.gate.GATE_10_MULTISEED);

%% GATE 12: BLIND EVALUATION
fprintf('[PHASE 12] Blind evaluation (both populations)...\n');
run = core.evaluate_predictions(run, cfg);
check_gate(run.gate.GATE_12_BLIND_EVALUATION,'Gate 12');
fprintf('[GATE_12] BLIND_EVALUATION = %s\n\n', run.gate.GATE_12_BLIND_EVALUATION);

%% ALL-MODEL BLIND COMPARISON (Tahap 6, after Gate 12)
fprintf('[TAHAP 6] All-model blind comparison...\n');
try
    run = core.export_all_model_blind(run, cfg);
catch ME_am
    fprintf('[WARN] All-model blind: %s\n', ME_am.message);
end

%% DIRECT RIDGE AUDIT (Priorities 4,5 — after all-model export)
fprintf('[TAHAP 4/5] Direct Ridge leakage/alignment/post-hoc audit...\n');
try
    run = core.audit_direct_ridge(run, cfg);
catch ME_dra
    fprintf('[WARN] Direct Ridge audit: %s\n', ME_dra.message);
end

%% GATE 13: GEOMECHANICS
fprintf('[PHASE 13] Geomechanical analysis...\n');
run = core.compute_geomechanics(run, cfg);
check_gate(run.gate.GATE_13_GEOMECHANICS,'Gate 13');
fprintf('[GATE_13] GEOMECHANICS = %s\n\n', run.gate.GATE_13_GEOMECHANICS);

%% GATE 14: NUMERICAL FREEZE
fprintf('[PHASE 14] Freezing numerical run...\n');
run = core.freeze_numerical_run(run, cfg);
run = core.validate_numerical_run(run, cfg);
check_gate(run.gate.GATE_14_NUMERICAL_FREEZE,'Gate 14');
% Dual Gate-14 status (Priority 5)
if isfield(run.gate,'GATE_14_FROZEN_ARTIFACT_INTEGRITY')
    fprintf('[GATE_14] FROZEN_ARTIFACT_INTEGRITY = %s\n', run.gate.GATE_14_FROZEN_ARTIFACT_INTEGRITY);
end
if isfield(run.gate,'GATE_14_PUBLICATION_BUNDLE_INTEGRITY')
    fprintf('[GATE_14] PUBLICATION_BUNDLE_INTEGRITY = %s\n\n', run.gate.GATE_14_PUBLICATION_BUNDLE_INTEGRITY);
else
    fprintf('[GATE_14] PUBLICATION_BUNDLE_INTEGRITY = PENDING\n\n');
end



%% COMPLETION
fprintf('%s\n', repmat('=',1,65));
fprintf('  NUMERICAL_PIPELINE_COMPLETE\n');
fprintf('  Run ID: %s\n', run.id);
fprintf('  Folder: %s\n', run.folder);
fprintf('\n  Next: gse_report.generate_all(''%s'')\n', run.folder);
fprintf('%s\n\n', repmat('=',1,65));

% Close log
if isfield(run,'log_fid') && run.log_fid > 0
    fprintf(run.log_fid,'NUMERICAL_PIPELINE_COMPLETE\n');
    fclose(run.log_fid);
end

% Write completion flag
flag_path = fullfile(run.folder,'09_frozen','FROZEN_RUN_COMPLETE.flag');
fid_flag = fopen(flag_path,'w');
fprintf(fid_flag,'FROZEN_RUN_COMPLETE\nRUN_ID: %s\n', run.id);
fclose(fid_flag);

fprintf('  Gates 15-16 run separately:\n');
fprintf('  GATE_15: Run run_pipeline.m twice; compare run folders.\n');
fprintf('  GATE_16: gse_report.generate_all(run_folder)\n\n');

end  % main_numerical_pipeline

% ─────────────────────────────────────────────────────────────────────────────
function check_gate(status, gate_name)
if strcmp(status,'PASS')
    return;
elseif startsWith(status,'PASS_STUB')
    fprintf('  [WARN] %s = %s (stub — not publication-ready)\n', gate_name, status);
elseif startsWith(status,'FAIL')
    error('Pipeline:GateFail','%s FAILED: %s', gate_name, status);
else
    error('Pipeline:GatePending','%s unexpected status: %s', gate_name, status);
end
end
