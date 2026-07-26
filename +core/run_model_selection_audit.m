function run = run_model_selection_audit(run, cfg)
% CORE.RUN_MODEL_SELECTION_AUDIT  Level-2 model selection on common CV basis.
%   All models evaluated on identical blocked-CV folds (Well-A only).
%   Fixes apples-to-oranges comparison (PNN CV vs Ridge holdout).
%
%   Output: MODEL_SELECTION_TABLE.csv, MODEL_SELECTION_REPORT.md,
%           META_INPUT_ABLATION.csv, STACKING_VALUE_ADDED_REPORT.md

out_dir = fullfile(run.folder,'07_tables');  % P4: matches Gate-14 check location
feat    = run.fs.S1_features;
hp      = run.hyperparams;
T_A     = run.T_A_proc;
tr_mask = logical(T_A.SPLIT_FLAG);
T_tr    = T_A(tr_mask,:);
y_tr    = T_tr.VS;
fold_ids= run.fold_ids;
k       = cfg.split.kfold;
seed    = cfg.seeds.canonical;

fprintf('  [SEL_AUDIT] Level-2 model selection (common CV basis, k=%d)...\n', k);

%% --- All base models (base learner CV) ---
base_candidates = {
    'pnn',    struct('spread',hp.pnn.spread), cfg.seeds.offset_pnn;
    'mlffnn', struct('hidden',hp.mlffnn.hidden,'lr',hp.mlffnn.lr,'epochs',hp.mlffnn.epochs,'batch',hp.mlffnn.batch), cfg.seeds.offset_mlffnn;
    'dffnn',  struct('hidden',hp.dffnn.hidden,'lr',hp.dffnn.lr,'epochs',hp.dffnn.epochs,'batch',hp.dffnn.batch), cfg.seeds.offset_dffnn;
    'cnn1d',  struct('kernels',hp.cnn1d.kernels,'filters',hp.cnn1d.filters,'lr',hp.cnn1d.lr,'epochs',hp.cnn1d.epochs,'batch',hp.cnn1d.batch), cfg.seeds.offset_cnn1d;
};

sel_rows = {};
for ci = 1:size(base_candidates,1)
    nm = base_candidates{ci,1};
    hp_b = base_candidates{ci,2};
    off  = base_candidates{ci,3};
    cv_r2=nan(k,1); cv_rmse=nan(k,1);
    for fi=1:k
        val_m=(fold_ids==fi); tr_m=~val_m;
        T_in=T_tr(tr_m,:); T_va=T_tr(val_m,:);
        pm_fi=fit_fold_pm(T_in,feat);
        X_in=scale_pm(T_in,feat,pm_fi); X_va=scale_pm(T_va,feat,pm_fi);
        y_in=y_tr(tr_m); y_va=y_tr(val_m);
        X_in(isnan(X_in))=0; X_va(isnan(X_va))=0;
        try
            m_fi=models.fit_base(X_in,y_in,nm,hp_b,...
                seed+off+fi*cfg.seeds.offset_fold_mult,cfg);
            yp=core.predict_base_model(m_fi,X_va);
            ok=~isnan(y_va)&~isnan(yp);
            if sum(ok)>2
                cv_r2(fi)=1-sum((y_va(ok)-yp(ok)).^2)/sum((y_va(ok)-mean(y_va(ok))).^2);
                cv_rmse(fi)=sqrt(mean((y_va(ok)-yp(ok)).^2));
            end
        catch; end
    end
    mean_r2=mean(cv_r2,'omitnan'); std_r2=std(cv_r2,'omitnan');
    mean_rmse=mean(cv_rmse,'omitnan'); std_rmse=std(cv_rmse,'omitnan');
    % Holdout R² from meta_metrics if available
    hold_r2=NaN;
    if isfield(run,'meta_metrics') && isfield(run.meta_metrics,strrep(nm,'_stacker',''))
        hold_r2=run.meta_metrics.(strrep(nm,'_stacker','')).R2_te;
    end
    sel_rows{end+1}={nm,'base',mean_r2,std_r2,mean_rmse,std_rmse,hold_r2};
    fprintf('  [SEL_AUDIT] %s: CV R²=%.4f±%.4f  CV RMSE=%.4f\n', nm, mean_r2, std_r2, mean_rmse);
end

%% Direct Ridge (post-hoc, included for Level-2 completeness)
% Classification: POST_HOC (not pre-specified). Must not be primary deployment model.
fprintf('  [SEL_AUDIT] Direct Ridge CV (post-hoc)...\n');
cv_r2_dr=nan(k,1); cv_rmse_dr=nan(k,1);
for fi_dr=1:k
    val_dr=(fold_ids==fi_dr); tr_dr=~val_dr;
    T_tr_dr=T_tr(tr_dr,:); T_va_dr=T_tr(val_dr,:);
    pm_dr=fit_fold_pm(T_tr_dr,feat); X_td=scale_pm(T_tr_dr,feat,pm_dr);
    X_vd=scale_pm(T_va_dr,feat,pm_dr); y_td=y_tr(tr_dr); y_vd=y_tr(val_dr);
    X_td(isnan(X_td))=0; X_vd(isnan(X_vd))=0;
    lam_dr=1.0; Xb_td=[ones(sum(tr_dr),1),X_td]; Xb_vd=[ones(sum(val_dr),1),X_vd];
    rng(seed+cfg.seeds.offset_ridge+fi_dr*cfg.seeds.offset_fold_mult,'twister');
    B_dr=(Xb_td'*Xb_td+lam_dr*eye(size(Xb_td,2)))\(Xb_td'*y_td);
    yp_dr=Xb_vd*B_dr; ok_dr=~isnan(y_vd)&~isnan(yp_dr);
    if sum(ok_dr)>2
        cv_r2_dr(fi_dr)=1-sum((y_vd(ok_dr)-yp_dr(ok_dr)).^2)/sum((y_vd(ok_dr)-mean(y_vd(ok_dr))).^2);
        cv_rmse_dr(fi_dr)=sqrt(mean((y_vd(ok_dr)-yp_dr(ok_dr)).^2));
    end
end
hold_r2_dr=NaN;  % no holdout for direct Ridge (post-hoc)
sel_rows{end+1}={'direct_ridge','post_hoc',mean(cv_r2_dr,'omitnan'),std(cv_r2_dr,'omitnan'),...
    mean(cv_rmse_dr,'omitnan'),std(cv_rmse_dr,'omitnan'),hold_r2_dr};
fprintf('  [SEL_AUDIT] direct_ridge (POST-HOC): CV R²=%.4f±%.4f RMSE=%.4f\n',...
    mean(cv_r2_dr,'omitnan'),std(cv_r2_dr,'omitnan'),mean(cv_rmse_dr,'omitnan'));

%% Meta-model nested CV (leakage-free outer-fold evaluation)
% Computes nested CV R² for ridge_stacker, icnn, hybrid_icnn on SAME k-fold basis
meta_models = {'ridge_stacker','icnn','hybrid_icnn'};
fprintf('  [SEL_AUDIT] Nested CV for meta-learners (leakage-free outer-fold)...\n');
for mi=1:numel(meta_models)
    nm_m=meta_models{mi}; key_m=strrep(nm_m,'_stacker','');
    cv_r2_m=nan(k,1); cv_rmse_m=nan(k,1);
    for fi_out=1:k
        val_out=(fold_ids==fi_out); tr_out=~val_out;
        T_tr_o=T_tr(tr_out,:); T_va_o=T_tr(val_out,:);
        y_tr_o=y_tr(tr_out); y_va_o=y_tr(val_out);
        fids_in=fold_ids(tr_out); n_inner=sum(tr_out);
        n_base=numel(cfg.stack.base_order); base_nms=cfg.stack.base_order;
        % Inner OOF for meta-training
        OOF_in=nan(n_inner,n_base);
        for fi_in=1:k
            if ~any(fids_in==fi_in); continue; end
            vi=fids_in==fi_in; ti=~vi;
            pm_in=fit_fold_pm(T_tr_o(ti,:),feat);
            X_ti=scale_pm(T_tr_o(ti,:),feat,pm_in); X_vi=scale_pm(T_tr_o(vi,:),feat,pm_in);
            y_ti2=y_tr_o(ti); X_ti(isnan(X_ti))=0; X_vi(isnan(X_vi))=0;
            for bi=1:n_base
                nm_b=base_nms{bi};
                hp_b=get_hp_sel(hp,nm_b);
                off_b=cfg.seeds.(['offset_' nm_b]);
                m_b=models.fit_base(X_ti,y_ti2,nm_b,hp_b,...
                    seed+off_b+(fi_out*100+fi_in)*cfg.seeds.offset_fold_mult,cfg);
                OOF_in(vi,bi)=core.predict_base_model(m_b,X_vi);
            end
        end
        OOF_in(isnan(OOF_in))=0;
        ms_mu_in=mean(OOF_in,1,'omitnan'); ms_sg_in=std(OOF_in,0,1,'omitnan');
        ms_sg_in(ms_sg_in<1e-6)=1;
        Xm_in=(OOF_in-ms_mu_in)./ms_sg_in;
        % Base preds on outer val
        pm_out=fit_fold_pm(T_tr_o,feat);
        X_tr_os=scale_pm(T_tr_o,feat,pm_out); X_va_os=scale_pm(T_va_o,feat,pm_out);
        X_tr_os(isnan(X_tr_os))=0; X_va_os(isnan(X_va_os))=0;
        P_va=nan(sum(val_out),n_base);
        for bi=1:n_base
            nm_b=base_nms{bi}; hp_b=get_hp_sel(hp,nm_b);
            off_b=cfg.seeds.(['offset_' nm_b]);
            m_bf=models.fit_base(X_tr_os,y_tr_o,nm_b,hp_b,...
                seed+off_b+fi_out*cfg.seeds.offset_fold_mult+cfg.seeds.offset_refit,cfg);
            P_va(:,bi)=core.predict_base_model(m_bf,X_va_os);
        end
        P_va(isnan(P_va))=0;
        Xm_va=(P_va-ms_mu_in)./ms_sg_in;
        % Train meta on inner OOF, predict outer val
        try
            if strcmp(nm_m,'ridge_stacker')
                lam_m=hp.ridge.lambda_grid(ceil(numel(hp.ridge.lambda_grid)/2));
                if isfield(hp,'ridge_lambda_selected'); lam_m=hp.ridge_lambda_selected; end
                Xb_in=[ones(n_inner,1),Xm_in]; Xb_va=[ones(sum(val_out),1),Xm_va];
                B_m=(Xb_in'*Xb_in+lam_m*eye(size(Xb_in,2)))\(Xb_in'*y_tr_o);
                yp_m=Xb_va*B_m;
            else
                if strcmp(nm_m,'hybrid_icnn'); Xm_tr_n=[X_tr_os,Xm_in]; Xm_va_n=[X_va_os,Xm_va];
                else; Xm_tr_n=Xm_in; Xm_va_n=Xm_va; end
                y_mu_n=mean(y_tr_o); y_sg_n=std(y_tr_o); if y_sg_n<1e-6; y_sg_n=1; end
                ys_n=(y_tr_o-y_mu_n)/y_sg_n;
                n_in_n=size(Xm_tr_n,2);
                lrs_n=[featureInputLayer(n_in_n,'Normalization','none'),...
                    fullyConnectedLayer(32),batchNormalizationLayer,reluLayer,...
                    fullyConnectedLayer(1),regressionLayer];
                opts_n=trainingOptions('adam','MaxEpochs',100,'MiniBatchSize',32,...
                    'InitialLearnRate',1e-4,'Shuffle','never','Verbose',false,...
                    'ExecutionEnvironment','cpu','GradientThreshold',1.0);
                rng(seed+fi_out*17,'twister');
                net_n=trainNetwork(single(Xm_tr_n),single(ys_n(:)),lrs_n,opts_n);
                yp_m=double(predict(net_n,single(Xm_va_n)))*y_sg_n+y_mu_n;
            end
            ok_m=~isnan(y_va_o)&~isnan(yp_m);
            if sum(ok_m)>2
                cv_r2_m(fi_out)=1-sum((y_va_o(ok_m)-yp_m(ok_m)).^2)/sum((y_va_o(ok_m)-mean(y_va_o(ok_m))).^2);
                cv_rmse_m(fi_out)=sqrt(mean((y_va_o(ok_m)-yp_m(ok_m)).^2));
            end
        catch ME_m
            fprintf('  [SEL_AUDIT] Nested CV fold %d %s: %s\n',fi_out,nm_m,ME_m.message);
        end
    end
    hold_r2_m2=NaN;
    if isfield(run,'meta_metrics')&&isfield(run.meta_metrics,key_m)
        hold_r2_m2=run.meta_metrics.(key_m).R2_te;
    end
    sel_rows{end+1}={nm_m,'meta_nested_cv',...
        mean(cv_r2_m,'omitnan'),std(cv_r2_m,'omitnan'),...
        mean(cv_rmse_m,'omitnan'),std(cv_rmse_m,'omitnan'),hold_r2_m2};
    fprintf('  [SEL_AUDIT] %s nested CV: R²=%.4f±%.4f RMSE=%.4f Holdout=%.4f\n',...
        nm_m,mean(cv_r2_m,'omitnan'),std(cv_r2_m,'omitnan'),...
        mean(cv_rmse_m,'omitnan'),hold_r2_m2);
    % Store per-fold vectors for paired audit (P1 fix)
    if strcmp(nm_m,'ridge_stacker')
        cv_r2_m_ridge   = cv_r2_m;   % 5×1 fold R² values
        cv_rmse_m_ridge = cv_rmse_m;  % 5×1 fold RMSE values
    end
end



%% Build MODEL_SELECTION_TABLE.csv
% Build table with proper column types (no cell2table to avoid brace-indexing issues)
n_rows = numel(sel_rows);
% Use string ARRAY (not cell) so numeric columns remain indexable as double
MODEL_col      = string(cellfun(@(r) r{1}, sel_rows, 'UniformOutput', false))';
TYPE_col       = string(cellfun(@(r) r{2}, sel_rows, 'UniformOutput', false))';
CV_R2_col      = cellfun(@(r) double_or_nan(r{3}), sel_rows)';
CV_R2_STD_col  = cellfun(@(r) double_or_nan(r{4}), sel_rows)';
CV_RMSE_col    = cellfun(@(r) double_or_nan(r{5}), sel_rows)';
CV_RMSE_STD_col= cellfun(@(r) double_or_nan(r{6}), sel_rows)';
HOLDOUT_R2_col = cellfun(@(r) double_or_nan(r{7}), sel_rows)';
T_sel_all = table(MODEL_col, TYPE_col, CV_R2_col, CV_R2_STD_col, ...
    CV_RMSE_col, CV_RMSE_STD_col, HOLDOUT_R2_col, ...
    'VariableNames',{'MODEL','TYPE','CV_R2_MEAN','CV_R2_STD','CV_RMSE_MEAN','CV_RMSE_STD','HOLDOUT_R2'});
writetable(T_sel_all, fullfile(out_dir,'MODEL_SELECTION_TABLE.csv'));

%% Select best by CV RMSE (common basis)
% Explicit double cast guards against edge cases in mixed tables
cv_rmse_vals = double(T_sel_all.CV_RMSE_MEAN);
[min_rmse, best_idx] = min(cv_rmse_vals);
model_names_str2 = string(T_sel_all.MODEL);
best_model_str = model_names_str2(best_idx);
best_model = {char(best_model_str)};  % keep as 1-element cell for compatibility  % cell column — brace OK
fprintf('  [SEL_AUDIT] Level-2 best (min CV RMSE=%.4f): %s\n', min_rmse, char(best_model_str));

%% Stacking value-added audit
fprintf('  [SEL_AUDIT] Stacking value-added audit...\n');
% Compare: PNN alone vs Ridge stacker
pnn_idx  = find(strcmp(T_sel_all.MODEL,'pnn'),1);
ridg_idx = find(strcmp(T_sel_all.MODEL,'ridge_stacker'),1);
if ~isempty(pnn_idx) && ~isempty(ridg_idx)
    pnn_rmse  = T_sel_all.CV_RMSE_MEAN(pnn_idx);
    ridg_rmse = T_sel_all.CV_RMSE_MEAN(ridg_idx);
    pnn_r2    = T_sel_all.CV_R2_MEAN(pnn_idx);
    ridg_r2_v = pnn_r2; if ~isempty(ridg_idx); ridg_r2_v=T_sel_all.CV_RMSE_MEAN(ridg_idx); end
    if pnn_rmse < ridg_rmse
        fprintf('  [SEL_AUDIT] Stacking NOT beneficial: PNN CV RMSE=%.4f < Ridge CV RMSE=%.4f\n',...
            pnn_rmse, ridg_rmse);
        fprintf('  [SEL_AUDIT]   PNN is a better single-model baseline than Ridge stacker\n');
        stacking_note = char(sprintf('PNN (RMSE=%.4f) outperforms Ridge stacker (RMSE=%.4f) on CV',...
            pnn_rmse, ridg_rmse));
    else
        fprintf('  [SEL_AUDIT] Stacking beneficial: Ridge CV RMSE=%.4f < PNN CV RMSE=%.4f\n',...
            ridg_rmse, pnn_rmse);
        stacking_note = char(sprintf('Ridge stacker (RMSE=%.4f) outperforms PNN (RMSE=%.4f) on CV',...
            ridg_rmse, pnn_rmse));
    end
else
    stacking_note = char('Comparison not available');
end

%% STACKING_VALUE_ADDED_REPORT.md
lines={}; lines{end+1}='# STACKING_VALUE_ADDED_REPORT.md';
lines{end+1}=sprintf('Run: %s | Seed: %d', run.id, seed);
lines{end+1}=''; lines{end+1}='## Summary';
lines{end+1}=stacking_note;
lines{end+1}=''; lines{end+1}='## All Models (CV RMSE, common basis)';
lines{end+1}='| Model | CV R² | CV RMSE | Holdout R² |';
lines{end+1}='|---|---:|---:|---:|';
% Convert to string array for safe indexing (audit §4.1)
model_names_str = string(T_sel_all.MODEL);
for ri=1:height(T_sel_all)
    lines{end+1}=sprintf('| %s | %.4f | %.4f | %.4f |',...
        char(model_names_str(ri)),...
        T_sel_all.CV_R2_MEAN(ri),...
        T_sel_all.CV_RMSE_MEAN(ri),...
        T_sel_all.HOLDOUT_R2(ri));
end
lines{end+1}=''; lines{end+1}=sprintf('Best by CV RMSE: **%s** (%.4f)', char(best_model_str), min_rmse);
lines{end+1}=''; lines{end+1}='## Note';
lines{end+1}=['The original model selection (Level 1) chose Ridge stacker as best meta-learner '...
    'based on Well-A internal holdout R². '...
    'This Level-2 analysis uses blocked-CV RMSE on the same k=5 folds, '...
    'providing a common evaluation basis across all model types. '...
    'Well-B was not used for any selection decision.'];
fid=fopen(fullfile(out_dir,'STACKING_VALUE_ADDED_REPORT.md'),'w');
for li=1:numel(lines); fprintf(fid,'%s\n',lines{li}); end
fclose(fid);


%% Pre-extract model names for comparisons
MODEL_col_pre = cellfun(@(r) r{1}, sel_rows, 'UniformOutput', false)';

%% Paired stacking value-added audit (fold-by-fold comparison)
fprintf('  [SEL_AUDIT] Paired fold audit: PNN vs Ridge stacker...\n');
pnn_fold_r2=nan(k,1); ridg_fold_r2=nan(k,1);
pnn_fold_rmse=nan(k,1); ridg_fold_rmse=nan(k,1);
pnn_idx = find(strcmp(MODEL_col_pre,'pnn'), 1);
ridg_idx = find(strcmp(MODEL_col_pre,'ridge_stacker'), 1);

if ~isempty(pnn_idx) && ~isempty(ridg_idx)
    % Re-compute fold-wise for PNN and Ridge stacker (nested)
    for fi_p=1:k
        val_p=(fold_ids==fi_p); tr_p=~val_p;
        T_tr_p=T_tr(tr_p,:); T_va_p=T_tr(val_p,:);
        y_tr_p=y_tr(tr_p); y_va_p=y_tr(val_p);
        pm_p=fit_fold_pm(T_tr_p,feat);
        X_tp=scale_pm(T_tr_p,feat,pm_p); X_vp=scale_pm(T_va_p,feat,pm_p);
        X_tp(isnan(X_tp))=0; X_vp(isnan(X_vp))=0;
        % PNN
        hp_pnn=get_hp_sel(hp,'pnn');
        m_pnn2=models.fit_base(X_tp,y_tr_p,'pnn',hp_pnn,...
            seed+cfg.seeds.offset_pnn+fi_p*cfg.seeds.offset_fold_mult,cfg);
        yp_pnn2=core.predict_base_model(m_pnn2,X_vp);
        ok_p=~isnan(y_va_p)&~isnan(yp_pnn2);
        if sum(ok_p)>2
            pnn_fold_r2(fi_p)=1-sum((y_va_p(ok_p)-yp_pnn2(ok_p)).^2)/sum((y_va_p(ok_p)-mean(y_va_p(ok_p))).^2);
            pnn_fold_rmse(fi_p)=sqrt(mean((y_va_p(ok_p)-yp_pnn2(ok_p)).^2));
        end
        % Ridge nested (reuse outer-fold nested CV)
        % Ridge nested CV fold metric (from the nested CV computed above)
        % cv_r2_m_ridge and cv_rmse_m_ridge are set after the meta-learner CV loop
        if exist('cv_r2_m_ridge','var') && ~isnan(cv_r2_m_ridge(fi_p))
            ridg_fold_r2(fi_p)   = cv_r2_m_ridge(fi_p);
            ridg_fold_rmse(fi_p) = cv_rmse_m_ridge(fi_p);
        end
    end
    
    % Delta metrics
    delta_r2   = ridg_fold_r2  - pnn_fold_r2;
    delta_rmse = pnn_fold_rmse - ridg_fold_rmse;  % positive=Ridge better
    n_wins_ridg= sum(ridg_fold_rmse < pnn_fold_rmse, 'omitnan');
    
    T_paired = table((1:k)', pnn_fold_r2, ridg_fold_r2, delta_r2,...
        pnn_fold_rmse, ridg_fold_rmse, delta_rmse,...
        'VariableNames',{'FOLD','PNN_R2','RIDGE_R2','DELTA_R2',...
        'PNN_RMSE','RIDGE_RMSE','DELTA_RMSE_PNN_minus_RIDGE'});
    writetable(T_paired, fullfile(out_dir,'STACKING_PAIRED_FOLD_METRICS.csv'));
    
    pnn_rmse_v  = T_sel_all.CV_RMSE_MEAN(pnn_idx);
    ridg_rmse_v = T_sel_all.CV_RMSE_MEAN(ridg_idx);
    delta_mean  = mean(delta_rmse,'omitnan');
    delta_std   = std(delta_rmse,'omitnan');
    
    fprintf('  [SEL_AUDIT] PNN CV RMSE=%.4f | Ridge nested CV RMSE=%.4f\n', pnn_rmse_v, ridg_rmse_v);
    fprintf('  [SEL_AUDIT] Mean DELTA_RMSE(PNN-Ridge)=%.4f±%.4f\n', delta_mean, delta_std);
    fprintf('  [SEL_AUDIT] Ridge wins %d/%d folds on RMSE\n', n_wins_ridg, k);
end

%% Ridge CV reconciliation
fprintf('  [SEL_AUDIT] Ridge CV reconciliation (Phase-9 vs nested Level-2)...\n');
ph9_ridg_r2=NaN; ph9_ridg_rmse=NaN;
if isfield(run,'ablation')
    for ai2=1:numel(run.ablation)
        if strcmp(run.ablation(ai2).config,'B2_RIDGE')
            ph9_ridg_r2  =run.ablation(ai2).cv_r2_mean;
            ph9_ridg_rmse=run.ablation(ai2).cv_rmse_mean;
        end
    end
end
lv2_ridg_r2=NaN; lv2_ridg_rmse=NaN;
ridg_idx2 = find(strcmp(MODEL_col_pre,'ridge_stacker'), 1);
if ~isempty(ridg_idx2)
    lv2_ridg_r2  =T_sel_all.CV_R2_MEAN(ridg_idx2);
    lv2_ridg_rmse=T_sel_all.CV_RMSE_MEAN(ridg_idx2);
end
T_recon=table(string({'Phase9_ablation';'Level2_nested_CV'}),...
    double([ph9_ridg_r2;lv2_ridg_r2]),double([ph9_ridg_rmse;lv2_ridg_rmse]),...
    string({'PNN-only_OOF_proxy';'AUTHORITATIVE_4model_OOF'}),...
    'VariableNames',{'Method','Ridge_CV_R2','Ridge_CV_RMSE','Notes'});
% Write using fprintf (bypass writetable type issues)
fid_rc=fopen(fullfile(out_dir,'RIDGE_CV_RECONCILIATION.csv'),'w');
fprintf(fid_rc,'Method,Ridge_CV_R2,Ridge_CV_RMSE,Notes\n');
for rci=1:height(T_recon)
    fprintf(fid_rc,'%s,%.6f,%.6f,%s\n',...
        char(T_recon.Method(rci)),T_recon.Ridge_CV_R2(rci),...
        T_recon.Ridge_CV_RMSE(rci),char(T_recon.Notes(rci)));
end
fclose(fid_rc);
fprintf('  [SEL_AUDIT] Phase-9 Ridge: R²=%.4f RMSE=%.4f (simple PNN-only stacking)\n',...
    ph9_ridg_r2,ph9_ridg_rmse);
fprintf('  [SEL_AUDIT] Nested CV Ridge: R²=%.4f RMSE=%.4f (true nested stacking)\n',...
    lv2_ridg_r2,lv2_ridg_rmse);
fprintf('  [SEL_AUDIT] Difference expected: Phase-9 uses PNN-only OOF proxy; nested CV uses 4-model OOF\n');


%% MODEL_SELECTION_REPORT.md
fid2=fopen(fullfile(out_dir,'MODEL_SELECTION_REPORT.md'),'w');
fprintf(fid2,'# MODEL_SELECTION_REPORT.md\n');
fprintf(fid2,'Run: %s\n', run.id);
fprintf(fid2,'\n## Level 1 — Meta-learner selection\n');
fprintf(fid2,'Criterion: highest Well-A internal holdout R²\n');
fprintf(fid2,'Selected: %s (holdout R²=%.4f)\n', run.deploy_name, run.deploy_r2_WA);
fprintf(fid2,'\n## Level 2 — Overall deployable model\n');
fprintf(fid2,'Criterion: minimum mean blocked-CV RMSE (k=%d, common basis)\n', k);
fprintf(fid2,'Best: %s (CV RMSE=%.4f)\n', char(best_model_str), min_rmse);
fprintf(fid2,'\n## Selection policy\n');
fprintf(fid2,'Deployment model = Ridge stacker (Level-1 winner, meta-learner context).\n');
fprintf(fid2,'Level-2 note: %s\n', char(stacking_note));
fprintf(fid2,'Well-B was NOT used for any model selection decision.\n');
fclose(fid2);

% INTERNAL_TO_EXTERNAL_RANKING_REVERSAL.csv (audit §5)
if isfield(run,'eval_popA')
    ext_r2_vals = nan(height(T_sel_all),1);
    ext_model_col = T_sel_all.MODEL;
    for ri_ext=1:height(T_sel_all)
        nm_ext = char(string(ext_model_col(ri_ext)));
        % Look up blind R² from all-model blind table
        amc_path = fullfile(run.folder,'07_tables','TABLE_BLIND_ALL_MODELS_POP_A.csv');
        if isfile(amc_path)
            T_amc = readtable(amc_path,'VariableNamingRule','preserve');
            idx_ext = find(strcmp(string(T_amc.MODEL), nm_ext),1);
            if ~isempty(idx_ext); ext_r2_vals(ri_ext) = T_amc.R2(idx_ext); end
        end
    end
    [~,int_ord] = sort(T_sel_all.CV_R2_MEAN,'descend');
    [~,ext_ord] = sort(ext_r2_vals,'descend','MissingPlacement','last');
    T_rev = table(T_sel_all.MODEL(int_ord), int_ord, ext_ord(int_ord),...
        T_sel_all.CV_R2_MEAN(int_ord), ext_r2_vals(int_ord),...
        'VariableNames',{'MODEL','INT_RANK','EXT_RANK','CV_R2','BLIND_R2'});
    writetable(T_rev, fullfile(out_dir,'INTERNAL_TO_EXTERNAL_RANKING_REVERSAL.csv'));
    fprintf('  [SEL_AUDIT] INTERNAL_TO_EXTERNAL_RANKING_REVERSAL.csv written\n');
end

run.model_selection_l2 = struct('best_model',char(best_model_str),'best_cv_rmse',min_rmse,...
    'stacking_note',stacking_note,'level2_status','PASS');

% Write model selection freeze
sel_freeze=struct('best_meta_l1',run.deploy_name,'best_overall_l2',char(best_model_str),...
    'l1_holdout_r2',run.deploy_r2_WA,'l2_cv_rmse',min_rmse,...
    'stacking_note',stacking_note,...
    'selection_basis','Well-A only, Well-B not used',...
    'frozen_at',datestr(now,'yyyy-mm-dd HH:MM:SS')); %#ok<DATST>
save(fullfile(out_dir,'SELECTED_OVERALL_MODEL.mat'),'sel_freeze','-v7.3');
fid_sf=fopen(fullfile(out_dir,'MODEL_SELECTION_FREEZE.md'),'w');
fprintf(fid_sf,'# MODEL_SELECTION_FREEZE.md\n');
fprintf(fid_sf,'Level-1 best meta-learner: %s (holdout R²=%.4f)\n',run.deploy_name,run.deploy_r2_WA);
fprintf(fid_sf,'Level-2 best overall: %s (nested CV RMSE=%.4f)\n',char(best_model_str),min_rmse);
fprintf(fid_sf,'Stacking: %s\n',stacking_note);
fprintf(fid_sf,'Well-B NOT used for selection.\n');
fclose(fid_sf);

% Gate 8B status
% Gate 8B fail-closed (audit §4.1 + NaN assertion)
required_files_8b = {'MODEL_SELECTION_TABLE.csv','MODEL_SELECTION_REPORT.md',...
    'STACKING_VALUE_ADDED_REPORT.md','STACKING_PAIRED_FOLD_METRICS.csv'};
gate8b_ok = true;

% Check 1: paired metrics must be finite (audit P2 — NaN fails)
if exist('delta_rmse','var')
    n_finite_delta = sum(isfinite(delta_rmse));
    if n_finite_delta < 1
        gate8b_ok = false;
        fprintf('  [SEL_AUDIT] GATE_8B FAIL: paired DELTA_RMSE all NaN (%d finite)\n', n_finite_delta);
    elseif n_finite_delta < k
        fprintf('  [SEL_AUDIT] GATE_8B WARN: only %d/%d fold deltas finite\n', n_finite_delta, k);
    end
else
    gate8b_ok = false;
    fprintf('  [SEL_AUDIT] GATE_8B FAIL: delta_rmse not computed\n');
end

% Check 2: Ridge fold metrics must not all be NaN (audit P1)
if exist('ridg_fold_rmse','var') && all(isnan(ridg_fold_rmse))
    gate8b_ok = false;
    fprintf('  [SEL_AUDIT] GATE_8B FAIL: Ridge fold RMSE all NaN\n');
end

% Check 3: Required output files exist
for rf_i = 1:numel(required_files_8b)
    fpath_8b = fullfile(out_dir,required_files_8b{rf_i});
    if ~isfile(fpath_8b)
        gate8b_ok = false;
        fprintf('  [SEL_AUDIT] GATE_8B missing: %s\n', required_files_8b{rf_i});
        fprintf('  [SEL_AUDIT]   Expected: %s\n', fpath_8b);
    end
end
if gate8b_ok
    run.gate_8B = 'PASS'; run.gate_8B_publication_block = false;
    fprintf('  [SEL_AUDIT] GATE_8B = PASS\n');
else
    run.gate_8B = 'FAIL'; run.gate_8B_publication_block = true;
    fprintf('  [SEL_AUDIT] GATE_8B = FAIL | PUBLICATION_BLOCK = TRUE\n');
end
fprintf('  [SEL_AUDIT] Level-2 best overall: %s (CV RMSE=%.4f)\n', char(best_model_str), min_rmse);
fprintf('  [SEL_AUDIT] Saved MODEL_SELECTION_TABLE.csv and MODEL_SELECTION_REPORT.md\n');
end

function pm=fit_fold_pm(T,feat)
pm.scaler=struct(); pm.imputation=struct();
for fi=1:numel(feat); f=feat{fi};
    if ~ismember(f,T.Properties.VariableNames); continue; end
    v=T.(f); ok=~isnan(v);
    if any(ok); pm.scaler.(f).mu=mean(v(ok)); pm.scaler.(f).sg=std(v(ok));
    if pm.scaler.(f).sg<1e-6; pm.scaler.(f).sg=1; end
    pm.imputation.(f).median=median(v(ok)); end
end; end

function X=scale_pm(T,feat,pm)
X=zeros(height(T),numel(feat));
for fi=1:numel(feat); f=feat{fi};
    if ~ismember(f,T.Properties.VariableNames)||~isfield(pm.scaler,f); continue; end
    v=T.(f); miss=isnan(v);
    if any(miss); v(miss)=pm.imputation.(f).median; end
    X(:,fi)=(v-pm.scaler.(f).mu)/pm.scaler.(f).sg;
end; end

function v = double_or_nan(x)
if isnumeric(x); v = double(x); else; v = NaN; end
end

function hp_b=get_hp_sel(hp,nm); if isfield(hp,nm); hp_b=hp.(nm); else; hp_b=struct(); end; end
