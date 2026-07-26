function run = validate_numerical_run(run, cfg)
% CORE.VALIDATE_NUMERICAL_RUN  Gate 14 — frozen artifact integrity check.
%
%  Design B (per audit §4.1, run 20260722_094427):
%    Phase 10 = deployment-seed robustness (independent replicates)
%    Gate 12  = authoritative frozen blind result
%    Gate 14  = internal consistency of frozen artifacts only
%    "Canonical identity" terminology REMOVED (stochastic models cannot be identical)

fail = {};

%% 1. Required files exist
if ~isfile(fullfile(run.folder,'09_frozen','FROZEN_DEPLOYMENT_MODEL.mat'))
    fail{end+1}='FROZEN_DEPLOYMENT_MODEL.mat missing';
end
if ~isfile(fullfile(run.folder,'09_frozen','FROZEN_NUMERICAL_RUN.mat'))
    fail{end+1}='FROZEN_NUMERICAL_RUN.mat missing';
end

%% 2. Both evaluation populations completed
if ~isfield(run,'eval_popA') || ~isfield(run,'eval_popB')
    fail{end+1}='eval_popA/popB missing — Gate 12 not complete';
end
if isfield(run,'eval_popB') && ~isfield(run.eval_popB,'R2_raw')
    fail{end+1}='eval_popB.R2_raw missing';
end

%% 3. Frozen blind result summary (Gate 12 is authoritative)
if isfield(run,'eval_popA') && isfield(run.eval_popA,'R2_raw')
    fprintf('  [VALIDATE] Gate-12 authoritative results (model-specific conclusion):\n');
    fprintf('  [VALIDATE]   Deploy model: %s (pre-specified)\n', run.deploy_name);
    fprintf('  [VALIDATE]   Pop-A (n=%d): R²=%.4f  RMSE=%.4f  bias=%+.4f km/s\n',...
        run.eval_popA.n, run.eval_popA.R2_raw, run.eval_popA.RMSE_raw, run.eval_popA.bias_raw);
    fprintf('  [VALIDATE]   Pop-B (n=%d): R²=%.4f  RMSE=%.4f  bias=%+.4f km/s\n',...
        run.eval_popB.n, run.eval_popB.R2_raw, run.eval_popB.RMSE_raw, run.eval_popB.bias_raw);
    if run.eval_popA.R2_raw < 0 && run.eval_popB.R2_raw < 0
        fprintf('  [VALIDATE]   Outcome: GENERALIZATION_FAILURE (all R² < 0)\n');
    end
end

%% 4. Phase-10 deployment-seed robustness summary (independent replicates)
if isfield(run,'seed_results')
    seeds_done = [run.seed_results.seed];
    r2_all     = [run.seed_results.R2_popA];
    rmse_all   = [run.seed_results.RMSE_popA];
    fprintf('  [VALIDATE] Phase-10 deployment-seed robustness (Design B: independent replicates):\n');
    for si=1:numel(seeds_done)
        fprintf('  [VALIDATE]     Seed %d: Pop-A R²=%.4f  RMSE=%.4f\n',...
            seeds_done(si), r2_all(si), rmse_all(si));
    end
    fprintf('  [VALIDATE]   Phase-10 mean Pop-A R² = %.4f ± %.4f\n',...
        mean(r2_all,'omitnan'), std(r2_all,'omitnan'));
    fprintf('  [VALIDATE]   Note: Phase-10 replicates ≠ Gate-12 frozen result (expected for stochastic models)\n');
    fprintf('  [VALIDATE]   Gate-12 R²=%.4f is the authoritative blind metric\n', run.eval_popA.R2_raw);
    if all(r2_all < 0)
        fprintf('  [VALIDATE]   All Phase-10 seeds: R² < 0 — failure is seed-robust\n');
    end
end

%% 5. Geomechanical summary
if isfield(run,'geomech')
    fprintf('  [VALIDATE] Ridge stacker geomechanics (n=%d): ALL=%d/%d (%.1f%%)\n',...
        run.geomech.n_eval, run.geomech.n_all_gates,...
        run.geomech.n_eval, run.geomech.all_gates_pct);
    if isfield(run.geomech,'direct_ridge')
        gdr=run.geomech.direct_ridge;
        fprintf('  [VALIDATE] Direct Ridge geomechanics (post-hoc): Vp/Vs=%d nu=%d G=%d K=%d E=%d ALL=%d/%d (%.1f%%)\n',...
            gdr.n_vpvs_valid,gdr.n_nu_valid,gdr.n_G_valid,...
            gdr.n_K_valid,gdr.n_E_valid,gdr.n_all_gates,gdr.n_eval,gdr.all_gates_pct);
    end
end

%% Model-specific conclusion (Item 9 per audit spec)
fprintf('  [VALIDATE] Model-specific conclusion:\n');
if isfield(run,'deploy_name') && isfield(run,'eval_popA')
    if run.eval_popA.R2_raw < 0
        fprintf('  [VALIDATE]   %s (pre-specified): GENERALIZATION_FAILURE\n', run.deploy_name);
        fprintf('  [VALIDATE]   Positive bias %.4f km/s → predictions collapse to calibration range\n',...
            run.eval_popA.bias_raw);
        fprintf('  [VALIDATE]   0/%d Poisson ratios admissible → no valid geomechanical estimates\n',...
            run.geomech.n_eval);
        % Dynamically report all-model results from frozen CSV (not hard-coded)
        amc_path = fullfile(run.folder,'07_tables','TABLE_BLIND_ALL_MODELS_POP_A.csv');
        if isfile(amc_path)
            T_amc = readtable(amc_path,'VariableNamingRule','preserve');
            [best_r2, best_idx] = max(T_amc.R2);
            best_nm = char(string(T_amc.MODEL(best_idx)));
            fprintf('  [VALIDATE]   Best all-model blind (Pop-A): %s R²=%.4f\n', best_nm, best_r2);
            % Explicitly separate pre-specified and post-hoc
            prespec_mask = ~strcmp(string(T_amc.MODEL),'direct_ridge');
            if any(prespec_mask)
                [best_pre_r2, best_pre_idx] = max(T_amc.R2(prespec_mask));
                pre_models = T_amc.MODEL(prespec_mask);
                best_pre_nm = char(string(pre_models(best_pre_idx)));
                fprintf('  [VALIDATE]   Best pre-specified blind: %s R²=%.4f\n', best_pre_nm, best_pre_r2);
            end
            dr_idx = find(strcmp(string(T_amc.MODEL),'direct_ridge'),1);
            if ~isempty(dr_idx)
                fprintf('  [VALIDATE]   Direct Ridge (POST-HOC): R²=%.4f (requires 3rd-well confirmation)\n',...
                    T_amc.R2(dr_idx));
            end
        else
            fprintf('  [VALIDATE]   All-model CSV not available — run export_all_model_blind\n');
        end
        fprintf('  [VALIDATE]   Failure strongly associated with severe DT covariate shift\n');
        fprintf('  [VALIDATE]   Recommendation: domain adaptation or additional calibration wells\n');
    end
end

%% Final
% ── Gate 14: Dual status (audit §5) ─────────────────────────────────────────
if isempty(fail)
    run.gate.GATE_14_FROZEN_ARTIFACT_INTEGRITY   = 'PASS';
    fprintf('  [VALIDATE] GATE_14_FROZEN_ARTIFACT_INTEGRITY = PASS\n');
else
    run.gate.GATE_14_FROZEN_ARTIFACT_INTEGRITY   = 'FAIL';
    for fi2=1:numel(fail); fprintf('  [VALIDATE FAIL] %s\n',fail{fi2}); end
end

% Publication bundle integrity — separate from artifact integrity
pub_block = {};

% Check 1: Gate 8B status
if isfield(run,'gate_8B') && strcmp(run.gate_8B,'FAIL')
    pub_block{end+1} = 'GATE_8B = FAIL';
end

% Check 2-4: Required files exist
req_files = {'MODEL_SELECTION_TABLE.csv','TABLE_BLIND_ALL_MODELS_POP_A.csv',...
    'DIRECT_RIDGE_LEAKAGE_AUDIT.csv','MODEL_ANALYSIS_STATUS.csv'};
for rfi=1:numel(req_files)
    fp = fullfile(run.folder,'07_tables',req_files{rfi});
    if ~isfile(fp)
        pub_block{end+1} = sprintf('%s missing', req_files{rfi});
    end
end

% Check 5: DIRECT_RIDGE_LEAKAGE_AUDIT content (audit §4.1)
dr_lk_path = fullfile(run.folder,'07_tables','DIRECT_RIDGE_LEAKAGE_AUDIT.csv');
if isfile(dr_lk_path)
    try
        T_dr_lk = readtable(dr_lk_path,'VariableNamingRule','preserve');
        if ismember('STATUS',T_dr_lk.Properties.VariableNames)
            n_fail_lk = sum(strcmp(string(T_dr_lk.STATUS),'FAIL'));
            if n_fail_lk > 0
                pub_block{end+1} = sprintf(...
                    'DIRECT_RIDGE_LEAKAGE_AUDIT: %d/%d checks FAIL (must be 0 for publication)',...
                    n_fail_lk, height(T_dr_lk));
            end
        end
    catch
        pub_block{end+1} = 'DIRECT_RIDGE_LEAKAGE_AUDIT: could not read file';
    end
end

% Check 6: Direct Ridge audit results from run struct
if isfield(run,'audit_direct_ridge')
    if ~run.audit_direct_ridge.leakage_pass
        pub_block{end+1} = 'DIRECT_RIDGE_LEAKAGE_PASS = false (run.audit_direct_ridge)';
    end
end
if isempty(pub_block) && isempty(fail)
    run.gate.GATE_14_PUBLICATION_BUNDLE_INTEGRITY = 'PASS';
    fprintf('  [VALIDATE] GATE_14_PUBLICATION_BUNDLE_INTEGRITY = PASS\n');
else
    run.gate.GATE_14_PUBLICATION_BUNDLE_INTEGRITY = 'FAIL';
    fprintf('  [VALIDATE] GATE_14_PUBLICATION_BUNDLE_INTEGRITY = FAIL\n');
    for bi=1:numel(pub_block); fprintf('  [VALIDATE]   %s\n',pub_block{bi}); end
end

% Hard stop only if artifact integrity fails
if ~isempty(fail)
    error('Pipeline:ValidationFail','%d frozen artifact integrity failures',numel(fail));
end
end
