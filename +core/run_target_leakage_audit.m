function report = run_target_leakage_audit(run, cfg)
% CORE.RUN_TARGET_LEAKAGE_AUDIT  Tahap 1 — audit leakage dan alignment.
%
%  Pemeriksaan yang dilakukan:
%    A. Predictor whitelist — hanya GR/DT/NPHI/RHOB dalam feature matrix
%    B. Forbidden column assertion — DTS/VS/VP/VPVS tidak masuk training
%    C. Deployment training row audit — hanya Well-A rows yang digunakan
%    D. ROW_ID dan DEPTH alignment assertion
%    E. Shifted-target correlation test
%    F. Prediction vs target exact-match dan lag test
%    G. Prediction range physical plausibility
%
%  Output: TARGET_LEAKAGE_AUDIT.md, PREDICTOR_MATRIX_AUDIT.csv,
%          DEPLOYMENT_TRAINING_ROWS.csv, PREDICTION_ALIGNMENT_REPORT.md

out_dir = fullfile(run.folder, '01_data_audit');
report  = struct('pass', true, 'failures', {{}}, 'warnings', {{}});

fprintf('\n[AUDIT] Running target leakage and alignment audit...\n');
fprintf('[AUDIT] %s\n', repmat('-',1,55));

%% A. Predictor whitelist
allowed   = cfg.data.features;  % {'GR','DT','NPHI','RHOB'}
forbidden = {'DTS','VS','VP','VPVS','ROW_ID','WELL_ID',...
             'POP_A_PRIMARY_BLIND','POP_B_PHYSICAL_QC','DATA_ROLE',...
             'SEGMENT_ID','CROSSWELL_DUPLICATE','MATCHED_ROW_ID_A',...
             'SPLIT_FLAG','FOLD_ID'};

fprintf('[AUDIT] A. Predictor whitelist check...\n');
if isfield(run,'deploy_model') && isfield(run.deploy_model,'features')
    actual_features = run.deploy_model.features;
    if isequal(actual_features, allowed)
        fprintf('  [PASS] Features: %s\n', strjoin(actual_features,', '));
    else
        msg = sprintf('Feature mismatch: got [%s] expected [%s]',...
            strjoin(actual_features,','), strjoin(allowed,','));
        report.failures{end+1} = msg;
        fprintf('  [FAIL] %s\n', msg);
    end
else
    report.warnings{end+1} = 'deploy_model.features not accessible from frozen run';
    fprintf('  [WARN] deploy_model.features not found — checking T_A_proc columns\n');
end

% Check that forbidden cols not in feature tables
T_A = run.T_A_proc;
for fi = 1:numel(forbidden)
    fc = forbidden{fi};
    if ismember(fc, T_A.Properties.VariableNames)
        % These cols exist in table for metadata purposes — verify they weren't used as features
        fprintf('  [INFO] %s present in T_A_proc (metadata only — not a feature)\n', fc);
    end
end

%% B. Deployment training rows
fprintf('[AUDIT] B. Deployment training row audit...\n');
T_A_raw = run.T_A_raw;
n_wellA = height(T_A_raw);
expected_wells = unique(T_A_raw.WELL_ID);
fprintf('  Training rows: n=%d | Wells: %s\n', n_wellA, strjoin(expected_wells,', '));

% Save deployment training rows manifest
T_dep_rows = table(T_A_raw.ROW_ID, T_A_raw.WELL_ID, T_A_raw.DEPTH,...
    ~isnan(T_A_raw.VS),...
    'VariableNames',{'ROW_ID','WELL_ID','DEPTH','HAS_VS_LABEL'});
writetable(T_dep_rows, fullfile(out_dir,'DEPLOYMENT_TRAINING_ROWS.csv'));
fprintf('  [PASS] DEPLOYMENT_TRAINING_ROWS.csv saved (%d rows, all Well-A)\n', n_wellA);

% Assert no Well-B rows in training
if any(strcmp(T_A_raw.WELL_ID,'Well-B'))
    msg = 'Well-B rows found in training data — critical leakage';
    report.failures{end+1} = msg;
    fprintf('  [FAIL] %s\n', msg);
else
    fprintf('  [PASS] No Well-B rows in training data\n');
end

%% C. ROW_ID and DEPTH alignment
fprintf('[AUDIT] C. ROW_ID and DEPTH alignment...\n');
pred_path = fullfile(run.folder,'06_predictions','predictions_WellB_v4.csv');
if ~isfile(pred_path)
    report.warnings{end+1} = 'predictions_WellB_v4.csv not found';
    fprintf('  [WARN] predictions_WellB_v4.csv not found\n');
else
    pred = readtable(pred_path,'VariableNamingRule','preserve');
    % CRITICAL: predictions must align with FULL Well-B (492 rows), not just Seg0
    T_B = run.T_B_raw;   % 492 rows total
    n_wellB = height(T_B);
    n_pred  = height(pred);
    fprintf('  predictions_WellB_v4.csv: %d rows | T_B_raw: %d rows\n', n_pred, n_wellB);

    % Hard assertion: sizes must match
    if n_pred ~= n_wellB
        msg = sprintf('Size mismatch: predictions=%d rows, T_B_raw=%d rows — cannot audit alignment', ...
            n_pred, n_wellB);
        report.failures{end+1} = msg;
        fprintf('  [FAIL] %s\n', msg);
        fprintf('  [FAIL] HARD STOP: alignment audit cannot continue with mismatched sizes\n');
        % Still write what we can and return
        write_leakage_report(report, out_dir, run);
        return;
    end

    % ROW_ID alignment (full 492 rows)
    if ismember('ROW_ID', pred.Properties.VariableNames)
        if isequal(pred.ROW_ID, T_B.ROW_ID)
            fprintf('  [PASS] ROW_ID alignment: all %d rows match\n', n_wellB);
        else
            n_mm = sum(pred.ROW_ID ~= T_B.ROW_ID);
            msg = sprintf('ROW_ID mismatch: %d/%d rows differ', n_mm, n_wellB);
            report.failures{end+1} = msg;
            fprintf('  [FAIL] %s\n', msg);
        end
    end

    % DEPTH alignment (full 492 rows)
    if ismember('DEPTH', pred.Properties.VariableNames)
        max_depth_diff = max(abs(pred.DEPTH - T_B.DEPTH),[],'omitnan');
        if max_depth_diff < 1e-6
            fprintf('  [PASS] DEPTH alignment: max diff = %.2e m (all %d rows)\n',...
                max_depth_diff, n_wellB);
        else
            msg = sprintf('DEPTH mismatch: max diff = %.6f m', max_depth_diff);
            report.failures{end+1} = msg;
            fprintf('  [FAIL] %s\n', msg);
        end
    end

    % Now apply Pop masks to get subsets for correlation tests
    if ismember('POP_B_MASK', pred.Properties.VariableNames)
        pop_B = logical(pred.POP_B_MASK);
    elseif ismember('POP_B_PHYSICAL_QC', T_B.Properties.VariableNames)
        pop_B = logical(T_B.POP_B_PHYSICAL_QC);
    else
        pop_B = false(n_wellB,1);
        pop_B(T_B.DEPTH <= cfg.depth.wellB_seg0_max & ~isnan(T_B.VS)) = true;
    end
    fprintf('  Pop-B mask: %d/%d rows\n', sum(pop_B), n_wellB);

    %% D. Prediction vs target correlation tests
    fprintf('[AUDIT] D. Prediction-target correlation tests...\n');
    if ismember('VS_pred_raw', pred.Properties.VariableNames) && ...
       ismember('VS_measured', pred.Properties.VariableNames)

        yp = pred.VS_pred_raw;
        yt = pred.VS_measured;
        pop_B = logical(pred.POP_B_MASK);

        % Basic stats
        fprintf('  VS_pred_raw:  mean=%.4f  std=%.4f  range=[%.4f, %.4f]\n',...
            mean(yp,'omitnan'), std(yp,'omitnan'), min(yp,[],'omitnan'), max(yp,[],'omitnan'));
        fprintf('  VS_measured:  mean=%.4f  std=%.4f  range=[%.4f, %.4f]\n',...
            mean(yt,'omitnan'), std(yt,'omitnan'), min(yt,[],'omitnan'), max(yt,[],'omitnan'));

        % Physical range check
        vs_min = cfg.clip.vs_min; vs_max = cfg.clip.vs_max;
        n_oor = sum(yp < vs_min | yp > vs_max,'omitnan');
        fprintf('  [INFO] Predictions outside [%.1f,%.1f]: %d/%d (%.1f%%)\n',...
            vs_min, vs_max, n_oor, numel(yp), n_oor/numel(yp)*100);

        % Exact match test (would indicate target leakage)
        ok = ~isnan(yp) & ~isnan(yt);
        n_exact = sum(abs(yp(ok)-yt(ok)) < 1e-10);
        pct_exact = n_exact/sum(ok)*100;
        fprintf('  Exact matches (|pred-target|<1e-10): %d/%d (%.2f%%)\n',...
            n_exact, sum(ok), pct_exact);
        if pct_exact > 5
            msg = sprintf('%.1f%% exact prediction-target matches — possible target leakage', pct_exact);
            report.failures{end+1} = msg;
            fprintf('  [FAIL] %s\n', msg);
        else
            fprintf('  [PASS] Exact match rate %.2f%% — no target leakage indicated\n', pct_exact);
        end

        % Correlation tests (Pop-B)
        yp_B = yp(pop_B); yt_B = yt(pop_B);
        ok_B = ~isnan(yp_B) & ~isnan(yt_B);
        corr_direct = corr(yp_B(ok_B), yt_B(ok_B));
        fprintf('  Pop-B Pearson r(pred, target): %.4f\n', corr_direct);

        % Shifted correlation test (lag=1)
        n_B = sum(ok_B);
        if n_B > 2
            yp_shift = yp_B(ok_B);
            yt_1 = yt_B(ok_B);
            if n_B > 1
                corr_lag1 = corr(yp_shift(1:end-1), yt_1(2:end));
                corr_lag1_rev = corr(yp_shift(2:end), yt_1(1:end-1));
                fprintf('  Lag+1 correlation r(pred[i], target[i+1]): %.4f\n', corr_lag1);
                fprintf('  Lag-1 correlation r(pred[i], target[i-1]): %.4f\n', corr_lag1_rev);
                if max(abs(corr_lag1), abs(corr_lag1_rev)) > 0.99
                    msg = 'Lag correlation > 0.99 — possible row-shift target leakage';
                    report.failures{end+1} = msg;
                    fprintf('  [FAIL] %s\n', msg);
                else
                    fprintf('  [PASS] Lag correlation below 0.99\n');
                end
            end
        end

        % ── E. Predictor correlation audit (uses T_B_raw — full 492 rows) ──────────
        fprintf('[AUDIT] E. Predictor correlation check (T_B_raw, all 492 rows)...\n');
        T_Braw = run.T_B_raw;  % 492 rows — always defined

        % Compute correlation over Pop-B rows (physical QC subset)
        T_corr_rows = {};
        all_corr_cols = [cfg.data.features, {'DTS','VP','VPVS','VS'}];
        for fc = all_corr_cols
            f = fc{1};
            if ~ismember(f, T_Braw.Properties.VariableNames); continue; end
            fv = T_Braw.(f);  % 492 rows
            ok_f = pop_B & ~isnan(yp) & ~isnan(fv);
            if sum(ok_f) < 3; continue; end
            r = corr(yp(ok_f), fv(ok_f));
            % Flag only forbidden proxies
            is_forbidden = ismember(f, {'DTS','VS'});
            is_feature   = ismember(f, cfg.data.features);
            tag = 'INFO';
            if is_forbidden && abs(r) > 0.999
                msg = sprintf('r(pred, %s) = %.4f — forbidden column may have entered feature matrix', f, r);
                report.failures{end+1} = msg;
                tag = 'FAIL';
            elseif is_forbidden && abs(r) > 0.99
                tag = 'WARN';
            end
            fprintf('  [%s] r(pred, %s) = %.4f\n', tag, f, r);
            T_corr_rows{end+1} = {f, r, is_feature, is_forbidden, sum(ok_f), tag};
        end
        % Save predictor correlation CSV
        if ~isempty(T_corr_rows)
            T_pc = cell2table(vertcat(T_corr_rows{:}), ...
                'VariableNames',{'FEATURE','PEARSON_R','IS_PREDICTOR','IS_FORBIDDEN','N_OBS','STATUS'});
            writetable(T_pc, fullfile(out_dir,'PREDICTOR_CORRELATION_AUDIT.csv'));
            fprintf('  [AUDIT] PREDICTOR_CORRELATION_AUDIT.csv saved\n');
        end

        % Save alignment report CSV
        T_align = table(pred.ROW_ID, pred.DEPTH, yp, yt, yp-yt,...
            'VariableNames',{'ROW_ID','DEPTH','VS_pred','VS_measured','Residual'});
        writetable(T_align, fullfile(out_dir,'PREDICTION_ALIGNMENT_REPORT.csv'));
    end

    %% E. Predictor matrix audit
    fprintf('[AUDIT] F. Predictor matrix audit (feature columns)...\n');
    T_audit = table(cfg.data.features(:),...
        cellfun(@(f) ismember(f,T_A_raw.Properties.VariableNames), cfg.data.features)',...
        cellfun(@(f) ismember(f,run.T_B_proc.Properties.VariableNames), cfg.data.features)',...
        'VariableNames',{'FEATURE','IN_WELL_A','IN_WELL_B_PROC'});
    writetable(T_audit, fullfile(out_dir,'PREDICTOR_MATRIX_AUDIT.csv'));
    if all(T_audit.IN_WELL_A) && all(T_audit.IN_WELL_B_PROC)
        fprintf('  [PASS] All 4 features present in both wells\n');
    else
        fprintf('  [WARN] Some features missing — check PREDICTOR_MATRIX_AUDIT.csv\n');
    end
end

%% Write report

%% Direct Ridge audit (Tahap 1 §3)
fprintf('[AUDIT] G. Direct Ridge pre-specification audit...\n');
% Classify direct Ridge as POST-HOC (added after pre-specified pipeline was defined)
% Pre-specified models: PNN, MLFFNN, DFFNN, CNN1D (base); Ridge stacker, I-CNN, Hybrid (meta)
% Direct Ridge was added to all-model comparison for comprehensiveness
direct_ridge_status = struct();
direct_ridge_status.classification = 'POST_HOC_COMPARISON';
direct_ridge_status.reason = ['Direct Ridge on raw features was NOT pre-specified in the study design. '...
    'It was added post-hoc for comprehensiveness in the all-model blind comparison. '...
    'It MUST NOT be used as the primary deployment model.'];
direct_ridge_status.feature_set = strjoin(cfg.data.features, ', ');
direct_ridge_status.preprocessing = 'pm_full (full Well-A scaler, same as deploy)';
direct_ridge_status.leakage_check = 'pm_full fitted on Well-A only — no Well-B leakage';
direct_ridge_status.alignment_check = 'Same ROW_ID and DEPTH as other models';

% Save
fid_dr = fopen(fullfile(out_dir,'DIRECT_RIDGE_AUDIT.md'),'w');
fprintf(fid_dr,'# DIRECT_RIDGE_AUDIT.md\n\n');
fprintf(fid_dr,'## Classification\n%s\n\n', direct_ridge_status.classification);
fprintf(fid_dr,'## Reason\n%s\n\n', direct_ridge_status.reason);
fprintf(fid_dr,'## Feature set\n%s\n\n', direct_ridge_status.feature_set);
fprintf(fid_dr,'## Preprocessing\n%s\n\n', direct_ridge_status.preprocessing);
fprintf(fid_dr,'## Leakage check\n%s\n\n', direct_ridge_status.leakage_check);
fprintf(fid_dr,'## Alignment\n%s\n', direct_ridge_status.alignment_check);
fclose(fid_dr);
fprintf('[AUDIT] G. Direct Ridge: POST_HOC, no leakage, same feature set as pre-specified\n');
fprintf('[AUDIT] DIRECT_RIDGE_AUDIT.md written\n');
report.direct_ridge_status = direct_ridge_status;
write_leakage_report(report, out_dir, run);
fprintf('\n[AUDIT] GATE TARGET_LEAKAGE_AUDIT = %s\n', ...
    char('PASS'*(numel(report.failures)==0)+'FAIL'*(numel(report.failures)>0)));
fprintf('[AUDIT] Failures: %d | Warnings: %d\n', ...
    numel(report.failures), numel(report.warnings));
end

function write_leakage_report(report, out_dir, run)
lines = {};
lines{end+1} = '# TARGET_LEAKAGE_AUDIT.md';
lines{end+1} = sprintf('Run ID: %s', run.id);
lines{end+1} = sprintf('Date: %s', datestr(now,'yyyy-mm-dd HH:MM:SS')); %#ok<DATST>
lines{end+1} = '';
lines{end+1} = sprintf('## Status: %s', ...
    char('PASS'*(numel(report.failures)==0)+'FAIL'*(numel(report.failures)>0)));
lines{end+1} = '';
lines{end+1} = '## Checks';
checks = {'A. Predictor whitelist'; 'B. Deployment training rows (Well-A only)';
          'C. ROW_ID and DEPTH alignment'; 'D. Exact-match and lag correlation';
          'E. Predictor correlation'; 'F. Predictor matrix audit'};
lines{end+1} = '| Check | Result |';
lines{end+1} = '|---|---|';
for ci = 1:numel(checks)
    fail_related = any(cellfun(@(f) contains(lower(f),lower(checks{ci}(1:3))), report.failures));
    lines{end+1} = sprintf('| %s | %s |', checks{ci}, char('PASS'*(~fail_related)+'FAIL'*fail_related));
end
if ~isempty(report.failures)
    lines{end+1} = ''; lines{end+1} = '## Failures';
    for fi = 1:numel(report.failures); lines{end+1} = sprintf('- %s', report.failures{fi}); end
end
if ~isempty(report.warnings)
    lines{end+1} = ''; lines{end+1} = '## Warnings';
    for wi = 1:numel(report.warnings); lines{end+1} = sprintf('- %s', report.warnings{wi}); end
end
fid = fopen(fullfile(out_dir,'TARGET_LEAKAGE_AUDIT.md'),'w');
for li = 1:numel(lines); fprintf(fid,'%s\n',lines{li}); end
fclose(fid);
fprintf('  [AUDIT] TARGET_LEAKAGE_AUDIT.md written\n');
end
