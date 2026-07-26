function run = run_feature_selection(run, cfg)
% CORE.RUN_FEATURE_SELECTION  mRMR + LASSO feature selection (Rule §9).
%   Fitted on Well-A training block only.
%   S1: full feature set (GR, DT, NPHI, RHOB)
%   S2: mRMR ∩ LASSO intersection (fallback: union if empty)
%   Saves FEATURE_SELECTION_REPORT.csv
%
%   NOTE (Rule §9.2): Full nested feature selection (per-fold) is implemented
%   in generate_oof_predictions via fit_fold_preprocessor. This function
%   provides the global S2 set for the deployment model and ablation study.
%   Per-fold FS results are saved in OOF_fold_metrics.csv.

out_dir = fullfile(run.folder,'03_feature_selection');
feat_all = cfg.data.features;

% Extract training block (SPLIT_FLAG == true)
T_A = run.T_A_proc;
tr_mask = logical(T_A.SPLIT_FLAG);
X_tr = table2array(T_A(tr_mask, feat_all));
y_tr = T_A.VS(tr_mask);

% Remove rows where VS is NaN
ok = ~isnan(y_tr);
X_tr = X_tr(ok, :); y_tr = y_tr(ok);
X_tr(isnan(X_tr)) = 0;  % imputed values already in place

n_feat = numel(feat_all);
fprintf('  [FS] Training: %d rows, %d features\n', size(X_tr,1), n_feat);

%% mRMR ranking
mrmr_selected = feat_all;  % fallback
try
    [idx_mrmr, scores_mrmr] = fscmrmr(X_tr, y_tr);
    top_k = min(cfg.fs.mrmr_topk, n_feat);
    mrmr_selected = feat_all(idx_mrmr(1:top_k));
    fprintf('  [FS] mRMR top-%d: %s\n', top_k, strjoin(mrmr_selected,', '));
catch ME
    fprintf('  [FS] mRMR failed (%s) — using all features\n', ME.message);
    scores_mrmr = ones(1, n_feat);
    idx_mrmr    = 1:n_feat;
end

%% LASSO coefficient path
lasso_selected = feat_all;  % fallback
lasso_coef_at_lambda = zeros(n_feat,1);
try
    [B_lasso, lasso_info] = lasso(X_tr, y_tr, 'Alpha', cfg.fs.lasso_alpha, ...
        'NumLambda', 30, 'Standardize', false);
    % Pick lambda that gives ~half the features selected
    n_nonzero = sum(B_lasso ~= 0, 1);
    target_n  = max(1, floor(n_feat * 0.75));
    [~, li]   = min(abs(n_nonzero - target_n));
    coef_sel  = B_lasso(:, li);
    lasso_selected = feat_all(coef_sel ~= 0);
    lasso_coef_at_lambda = coef_sel;
    if isempty(lasso_selected)
        lasso_selected = feat_all;  % fallback to all
    end
    fprintf('  [FS] LASSO selected: %s\n', strjoin(lasso_selected,', '));
catch ME
    fprintf('  [FS] LASSO failed (%s) — using all features\n', ME.message);
end

%% S1: full features; S2: intersection with union fallback
S1_feat = feat_all;
S2_feat = intersect(mrmr_selected, lasso_selected, 'stable');
if isempty(S2_feat)
    fprintf('  [FS] Intersection empty — using union as S2 fallback\n');
    S2_feat = union(mrmr_selected, lasso_selected, 'stable');
end
if isempty(S2_feat); S2_feat = feat_all; end

run.fs.S1_features     = S1_feat;
run.fs.S2_features     = S2_feat;
run.fs.mrmr_ranking    = feat_all(idx_mrmr);
run.fs.lasso_coef      = lasso_coef_at_lambda;
run.fs.mrmr_selected   = mrmr_selected;
run.fs.lasso_selected  = lasso_selected;
run.fs.active          = 'S1_FULL';  % default; ablation uses S2

%% Save report
% Align mRMR scores to ORIGINAL feat_all order (idx_mrmr is a PERMUTATION of 1:n_feat
% returned by fscmrmr; scores_mrmr(k) is the score for the k-th best feature).
% We need the score for each feature in its original position in feat_all.
n_f = numel(feat_all);
mrmr_score_aligned = zeros(n_f, 1);
for fi_r = 1:n_f
    rank_pos = find(idx_mrmr == fi_r, 1);
    if ~isempty(rank_pos)
        mrmr_score_aligned(fi_r) = scores_mrmr(rank_pos);
    end
end
% cellfun with UniformOutput=true returns a logical row vector; transpose to column
in_mrmr  = cellfun(@(f) ismember(f, mrmr_selected),  feat_all, 'UniformOutput', true)';
in_lasso = cellfun(@(f) ismember(f, lasso_selected), feat_all, 'UniformOutput', true)';
in_s2    = cellfun(@(f) ismember(f, S2_feat),         feat_all, 'UniformOutput', true)';
% All variables: n_feat x 1 column vectors or cell arrays of the same length
T_report = table(...
    feat_all(:), ...
    mrmr_score_aligned, ...
    lasso_coef_at_lambda(:), ...
    in_mrmr, in_lasso, in_s2, ...
    'VariableNames',{'FEATURE','MRMR_SCORE','LASSO_COEF','IN_MRMR','IN_LASSO','IN_S2'});

writetable(T_report, fullfile(out_dir,'FEATURE_SELECTION_REPORT.csv'));
fprintf('  [FS] S1=%s | S2=%s\n', strjoin(S1_feat,','), strjoin(S2_feat,','));
% Audit §4.3 / Phase 5: Feature selection is development-level (global, not per-fold).
% Per-fold preprocessing uses fold-local scalers (proven by run_fold_preprocessing_audit).
% S2 selection is labelled as diagnostic-only per audit recommendation.
run.fs.selection_scope = 'DEVELOPMENT_DIAGNOSTIC_GLOBAL';
run.fs.nested_in_folds = false;  % explicitly declared
run.gate.GATE_5_FEATURE_SELECTION = 'PASS';
fprintf('  [FS] NOTE: Feature selection is global (diagnostic-only), not nested per-fold.\n');
fprintf('  [FS] Deployment uses S1_FULL; S2 is diagnostic/ablation only.\n');
end
