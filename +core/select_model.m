function run = select_model(run, cfg)
% CORE.SELECT_MODEL  Well-A-only model selection (Rule §13.3).
%   Candidates: ridge_stacker, icnn, hybrid_icnn (meta-learners only).
%   Policy: highest Well-A internal test R². Tie-break: simpler model first.
%   Well-B is NEVER used for selection.

candidates = cfg.stack.meta_candidates;  % {'ridge_stacker','icnn','hybrid_icnn'}
tie_thresh = cfg.stack.tie_thresh;
tie_order  = cfg.stack.tie_break_order;

mm = run.meta_metrics;

% Build candidate R² from Well-A test
r2_scores = struct();
for ci = 1:numel(candidates)
    nm = candidates{ci};
    nm_key = strrep(nm,'_stacker','');  % ridge_stacker → ridge
    if isfield(mm, nm_key) && isfield(mm.(nm_key),'R2_te')
        r2_scores.(nm) = mm.(nm_key).R2_te;
    else
        r2_scores.(nm) = -Inf;
    end
    fprintf('  [SELECT] %s: R2_WellA_test=%.4f\n', nm, r2_scores.(nm));
end

% Sort by R²
fn = fieldnames(r2_scores);
r2_vals = cellfun(@(f) r2_scores.(f), fn);
[sorted_r2, ord] = sort(r2_vals,'descend');
sorted_names = fn(ord);

best_name = sorted_names{1};
best_r2   = sorted_r2(1);

% Tie-break: if top models within tie_thresh, prefer simpler
if numel(sorted_r2) > 1 && (sorted_r2(1) - sorted_r2(2)) < tie_thresh
    for ti = 1:numel(tie_order)
        for si = 1:numel(sorted_names)
            if contains(sorted_names{si}, tie_order{ti}) && sorted_r2(si) >= best_r2-tie_thresh
                best_name = sorted_names{si};
                best_r2   = sorted_r2(si);
                fprintf('  [SELECT] Tie-break applied: %s preferred\n', best_name);
                break;
            end
        end
        break;
    end
end

run.deploy_name   = best_name;
run.deploy_r2_WA  = best_r2;
run.deploy_reason = sprintf('Highest Well-A test R2=%.4f among meta-learner candidates (Level 1: meta-learner only)', best_r2);

fprintf('  [SELECT] → %s (%s)\n', best_name, run.deploy_reason);

%% Level 2: Best OVERALL deployable model (base learners + meta-learners)
% Uses OOF CV metrics from Gate 7 and meta-test metrics from Gate 8
fprintf('  [SELECT] Level 2 — Overall model ranking (Well-A only):\n');

% Collect all model CV R² (from ablation B1-B4 if available)
all_r2 = struct();
if isfield(run,'ablation')
    for ai=1:numel(run.ablation)
        ab=run.ablation(ai);
        safe_nm=matlab.lang.makeValidName(ab.model);
        if isfield(all_r2,safe_nm)
            if ab.cv_r2_mean > all_r2.(safe_nm)
                all_r2.(safe_nm)=ab.cv_r2_mean;
            end
        else
            all_r2.(safe_nm)=ab.cv_r2_mean;
        end
    end
end
% Add meta-learner internal test R²
if isfield(run,'meta_metrics')
    fn_mm=fieldnames(run.meta_metrics);
    for mi=1:numel(fn_mm)
        nm_m=fn_mm{mi};
        if isfield(run.meta_metrics.(nm_m),'R2_te')
            safe_nm=matlab.lang.makeValidName(nm_m);
            if ~isfield(all_r2,safe_nm)
                all_r2.(safe_nm)=run.meta_metrics.(nm_m).R2_te;
            end
        end
    end
end

% Find best overall
fn_all=fieldnames(all_r2);
r2_vals_all=cellfun(@(f) all_r2.(f), fn_all);
[best_r2_overall, best_idx_overall]=max(r2_vals_all);
if ~isempty(fn_all)
    run.best_overall_model   = fn_all{best_idx_overall};
    run.best_overall_r2_WA   = best_r2_overall;
    % Level-2 summary (audit §3.3: Level-2 audit after Phase 9 is authoritative)
    fprintf('  [SELECT] Level-2 note: %s is best pre-specified by holdout R²=%.4f\n',...
        run.best_overall_model, best_r2_overall);
    fprintf('  [SELECT] Authoritative Level-2 from nested CV is computed after Phase 9\n');
    fprintf('  [SELECT] (See MODEL_SELECTION_TABLE.csv in 07_tables after full pipeline)\n');
end

% NOTE (Audit #9): Model selection uses single holdout R² (Well-A test set).
% This is conservative and honest given the leakage-free depth-blocked split.
% Cross-validated R² (e.g. from OOF folds) could be used instead.
% With only 98 test rows at this depth range, single-holdout is the practical choice.
% If GATE_6 hyperparameter tuning is implemented, use CV-R² from the HP search.
% Save selection report — all variables must be n×1 column vectors
r2_col      = cellfun(@(f) r2_scores.(f), fn);       % n×1 numeric (no transpose)
selected_col= cellfun(@(f) strcmp(f,best_name), fn); % n×1 logical (no transpose)
T_sel = table(fn(:), r2_col(:), selected_col(:), ...
    'VariableNames',{'MODEL','R2_WellA_test','SELECTED'});
out_dir = fullfile(run.folder,'04_model_development');
writetable(T_sel, fullfile(out_dir,'MODEL_SELECTION_REPORT.csv'));
end
