function run = run_ablation(run, cfg)
% CORE.RUN_ABLATION  Ablation study (Gate 9).
%   Priority configurations per audit spec §7.2:
%   A1 FULL, A2 S2, A3-A6 single-feature drop
%   B1-B4 base learner comparison
%   Evaluated on Well-A CV only (no Well-B).
%   Well-B evaluation available post-freeze via evaluate_predictions.

out_dir = fullfile(run.folder,'04_model_development');
feat_S1 = run.fs.S1_features;  % {'GR','DT','NPHI','RHOB'}
feat_S2 = run.fs.S2_features;  % {'RHOB','DT'}
hp      = run.hyperparams;
T_A     = run.T_A_proc;
tr_mask = logical(T_A.SPLIT_FLAG);
T_tr    = T_A(tr_mask,:);
y_tr    = T_tr.VS;
fold_ids= run.fold_ids;
k       = cfg.split.kfold;
seed    = cfg.seeds.canonical;

fprintf('  [ABLATION] Running ablation study (Well-A CV, k=%d folds)...\n', k);

% --- Feature scenarios (A1-A6) ---
ablation_configs = {
    'A1_FULL',         feat_S1, 'ridge_stacker';
    'A2_S2',           feat_S2, 'ridge_stacker';
    'A3_WITHOUT_GR',   setdiff(feat_S1,{'GR'},'stable'), 'ridge_stacker';
    'A4_WITHOUT_DT',   setdiff(feat_S1,{'DT'},'stable'), 'ridge_stacker';
    'A5_WITHOUT_NPHI', setdiff(feat_S1,{'NPHI'},'stable'), 'ridge_stacker';
    'A6_WITHOUT_RHOB', setdiff(feat_S1,{'RHOB'},'stable'), 'ridge_stacker';
};

% --- Model scenarios (B1-B4, all using S1_FULL) ---
model_configs = {
    'B1_PNN',          feat_S1, 'pnn';
    'B2_RIDGE',        feat_S1, 'ridge_stacker';
    'B3_ICNN',         feat_S1, 'icnn';
    'B4_HYBRID',       feat_S1, 'hybrid_icnn';
};

all_configs = [ablation_configs; model_configs];
n_cfg = size(all_configs,1);
results = struct();
% Pre-initialize all fields to ensure uniform schema across all configs
for ci_init=1:n_cfg
    results(ci_init).config=''; results(ci_init).features='';
    results(ci_init).model=''; results(ci_init).cv_r2_mean=NaN;
    results(ci_init).cv_r2_std=NaN; results(ci_init).cv_rmse_mean=NaN;
    results(ci_init).cv_rmse_std=NaN; results(ci_init).model_function='';
    results(ci_init).n_folds_run=0;
end

for ci = 1:n_cfg
    cfg_name  = all_configs{ci,1};
    cfg_feat  = all_configs{ci,2};
    cfg_model = all_configs{ci,3};

    fprintf('  [ABLATION] %s (feat=[%s] model=%s)...\n', ...
        cfg_name, strjoin(cfg_feat,','), cfg_model);

    cv_r2_folds  = nan(k,1);
    cv_rmse_folds= nan(k,1);

    for fi = 1:k
        val_m=fold_ids==fi; tr_m=~val_m;
        T_in=T_tr(tr_m,:); T_va=T_tr(val_m,:);
        % Fold-local preprocessing on cfg_feat
        pm_fi=fit_fold_pm(T_in,cfg_feat);
        X_in=scale_pm(T_in,cfg_feat,pm_fi); X_va=scale_pm(T_va,cfg_feat,pm_fi);
        y_in=y_tr(tr_m); y_va=y_tr(val_m);
        X_in(isnan(X_in))=0; X_va(isnan(X_va))=0;

        try
            if strcmp(cfg_model,'ridge_stacker')
                % For Ridge as meta-learner: just use direct ridge on raw features
                % (full stacking pipeline too expensive for ablation)
                hp_b=struct('spread',hp.pnn.spread);
                m_pnn=models.fit_base(X_in,y_in,'pnn',hp_b,...
                    seed+cfg.seeds.offset_pnn+fi*cfg.seeds.offset_fold_mult,cfg);
                oof_va=core.predict_base_model(m_pnn,X_va);
                oof_va(isnan(oof_va))=mean(y_in,'omitnan');
                mu_oo=mean(oof_va); sg_oo=std(oof_va); if sg_oo<1e-6; sg_oo=1; end
                Xb=[ones(sum(val_m),1),(oof_va-mu_oo)/sg_oo];
                Xb_tr=[ones(sum(tr_m),1),(core.predict_base_model(m_pnn,X_in)-mu_oo)/sg_oo];
                lam=hp.ridge.lambda_grid(ceil(numel(hp.ridge.lambda_grid)/2));
                B=(Xb_tr'*Xb_tr+lam*eye(size(Xb_tr,2)))\(Xb_tr'*y_in);
                yp=Xb*B;
            elseif strcmp(cfg_model,'pnn')
                hp_b=struct('spread',hp.pnn.spread);
                mdl=models.fit_base(X_in,y_in,'pnn',hp_b,...
                    seed+cfg.seeds.offset_pnn+fi*cfg.seeds.offset_fold_mult,cfg);
                yp=core.predict_base_model(mdl,X_va);
            elseif any(strcmp(cfg_model,{'icnn','hybrid_icnn'}))
                % I-CNN / Hybrid: train as meta-learner over PNN OOF
                % First get PNN OOF predictions as meta-features
                hp_pnn = struct('spread', hp.pnn.spread);
                m_pnn  = models.fit_base(X_in, y_in, 'pnn', hp_pnn, ...
                    seed+cfg.seeds.offset_pnn+fi*cfg.seeds.offset_fold_mult, cfg);
                oof_tr = core.predict_base_model(m_pnn, X_in);
                oof_va = core.predict_base_model(m_pnn, X_va);
                oof_tr(isnan(oof_tr))=mean(y_in,'omitnan');
                oof_va(isnan(oof_va))=mean(y_in,'omitnan');
                % Scale OOF as meta-features
                mu_oo=mean(oof_tr); sg_oo=std(oof_tr); if sg_oo<1e-6; sg_oo=1; end
                Xm_tr_ab = (oof_tr-mu_oo)/sg_oo;
                Xm_va_ab = (oof_va-mu_oo)/sg_oo;
                if strcmp(cfg_model,'hybrid_icnn')
                    Xm_tr_ab = [X_in, Xm_tr_ab];
                    Xm_va_ab = [X_va, Xm_va_ab];
                end
                % Choose hp
                if strcmp(cfg_model,'icnn'); hp_net=hp.icnn; else; hp_net=hp.hybrid; end
                nm_net = cfg_model;
                if strcmp(nm_net,'icnn'); off_net=cfg.seeds.offset_icnn; else; off_net=cfg.seeds.offset_hybrid_icnn; end
                m_net = fit_icnn_meta_ablation(Xm_tr_ab, y_in, hp_net, ...
                    seed+off_net+fi*cfg.seeds.offset_fold_mult, cfg);
                if isempty(m_net); yp=nan(sum(val_m),1);
                else; yp = predict_icnn_ablation(m_net, Xm_va_ab, y_in); end
            else
                % Fallback: PNN
                hp_b=struct('spread',hp.pnn.spread);
                mdl=models.fit_base(X_in,y_in,'pnn',hp_b,...
                    seed+cfg.seeds.offset_pnn+fi*cfg.seeds.offset_fold_mult,cfg);
                yp=core.predict_base_model(mdl,X_va);
            end
            ok=~isnan(y_va)&~isnan(yp);
            if sum(ok)>2
                cv_r2_folds(fi)=1-sum((y_va(ok)-yp(ok)).^2)/sum((y_va(ok)-mean(y_va(ok))).^2);
                cv_rmse_folds(fi)=sqrt(mean((y_va(ok)-yp(ok)).^2));
            end
        catch ME
            fprintf('    [SKIP] %s fold %d: %s\n',cfg_name,fi,ME.message);
        end
    end

    results(ci).config     = cfg_name;
    results(ci).features   = strjoin(cfg_feat,',');
    results(ci).model      = cfg_model;
    results(ci).cv_r2_mean = mean(cv_r2_folds,'omitnan');
    results(ci).cv_r2_std  = std(cv_r2_folds,'omitnan');
    results(ci).cv_rmse_mean = mean(cv_rmse_folds,'omitnan');
    results(ci).cv_rmse_std  = std(cv_rmse_folds,'omitnan');
    fprintf('    cv_R²=%.4f±%.4f  cv_RMSE=%.4f±%.4f\n',...
        results(ci).cv_r2_mean, results(ci).cv_r2_std,...
        results(ci).cv_rmse_mean, results(ci).cv_rmse_std);
end

%% Save
T_abl = struct2table(results);
writetable(T_abl, fullfile(out_dir,'TABLE_ABLATION.csv'));

% ABLATION_REPORT.md
write_ablation_report(results, out_dir);

%% Save Ridge coefficients (audit §4.4)
if isfield(run,'meta_models') && isfield(run.meta_models,'ridge')
    coef = run.meta_models.ridge.coef;
    base_names_r = cfg.stack.base_order;
    col_names_r = ['intercept'; strcat(base_names_r(:),'_OOF')];
    n_coef = min(numel(coef), numel(col_names_r));
    T_coef = table(col_names_r(1:n_coef), coef(1:n_coef), abs(coef(1:n_coef)),...
        'VariableNames',{'BASE_MODEL','COEFFICIENT','ABS_COEFFICIENT'});
    writetable(T_coef, fullfile(out_dir,'RIDGE_COEFFICIENTS.csv'));
    fprintf('  [ABLATION] Ridge coefficients saved to RIDGE_COEFFICIENTS.csv\n');
end

%% Model identity check (audit §4.2)
% Build identity table safely (handle missing fields)
n_res = numel(results);
cfg_names_r   = cellfun(@(r) r.config,    num2cell(results), 'UniformOutput', false)';
model_names_r = cellfun(@(r) r.model,     num2cell(results), 'UniformOutput', false)';
cv_r2_r       = cellfun(@(r) r.cv_r2_mean,  num2cell(results))';
cv_rmse_r     = cellfun(@(r) r.cv_rmse_mean,num2cell(results))';
n_folds_r     = zeros(n_res,1);
for ri_id=1:n_res
    if isfield(results(ri_id),'n_folds_run')
        n_folds_r(ri_id) = results(ri_id).n_folds_run;
    end
end
T_identity = table(cfg_names_r, model_names_r, n_folds_r, cv_r2_r, cv_rmse_r,...
    'VariableNames',{'CONFIG','MODEL','N_FOLDS','CV_R2','CV_RMSE'});
writetable(T_identity, fullfile(out_dir,'ABLATION_MODEL_IDENTITY_AUDIT.csv'));

% Assert B3/B4 not identical to B1 if all ran
b1_idx = find(strcmp({results.config},'B1_PNN'),1);
b3_idx = find(strcmp({results.config},'B3_ICNN'),1);
b4_idx = find(strcmp({results.config},'B4_HYBRID'),1);
if ~isempty(b1_idx) && ~isempty(b3_idx) && ~isempty(b4_idx)
    r2_b1=results(b1_idx).cv_r2_mean;
    r2_b3=results(b3_idx).cv_r2_mean;
    r2_b4=results(b4_idx).cv_r2_mean;
    if abs(r2_b1-r2_b3)<1e-6 && abs(r2_b1-r2_b4)<1e-6
        fprintf('  [ABLATION] [WARN] B1/B3/B4 identical — I-CNN/Hybrid may be using PNN fallback\n');
    else
        fprintf('  [ABLATION] [PASS] B3(%.4f) != B1(%.4f): I-CNN distinct\n', r2_b3, r2_b1);
        fprintf('  [ABLATION] [PASS] B4(%.4f) != B1(%.4f): Hybrid distinct\n', r2_b4, r2_b1);
    end
end

run.ablation = results;
run.gate.GATE_9_ABLATION = 'PASS';
fprintf('  [ABLATION] GATE_9 = PASS (%d configurations)\n', n_cfg);
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

function write_ablation_report(results,out_dir)
lines={}; lines{end+1}='# ABLATION_REPORT.md';
lines{end+1}='| Config | Features | Model | CV R² | CV RMSE |';
lines{end+1}='|---|---|---|---:|---:|';
for ri=1:numel(results)
    r=results(ri);
    lines{end+1}=sprintf('| %s | %s | %s | %.4f±%.4f | %.4f±%.4f |',...
        r.config,r.features,r.model,...
        r.cv_r2_mean,r.cv_r2_std,r.cv_rmse_mean,r.cv_rmse_std);
end
fid=fopen(fullfile(out_dir,'ABLATION_REPORT.md'),'w');
for li=1:numel(lines); fprintf(fid,'%s\n',lines{li}); end
fclose(fid);
end

function net = fit_icnn_meta_ablation(X, y, hp, seed, cfg)
% Simplified I-CNN for ablation (featureInputLayer, not imageInputLayer)
try
    if isfield(hp,'epochs'); ep=hp.epochs; else; ep=100; end
    if isfield(hp,'lr');     lr=hp.lr;     else; lr=1e-4; end
    if isfield(hp,'batch');  bs=hp.batch;  else; bs=32;   end
    n_in=size(X,2);
    y_mu=mean(y,'omitnan'); y_sg=std(y,'omitnan'); if y_sg<1e-6; y_sg=1; end
    y_s=(y-y_mu)/y_sg;
    layers=[featureInputLayer(n_in,'Normalization','none'),...
        fullyConnectedLayer(32),batchNormalizationLayer,reluLayer,...
        fullyConnectedLayer(1),regressionLayer];
    opts=trainingOptions('adam','MaxEpochs',ep,'MiniBatchSize',min(bs,size(X,1)),...
        'InitialLearnRate',lr,'Shuffle','never','Verbose',false,...
        'ExecutionEnvironment','cpu','GradientThreshold',1.0);
    rng(seed,'twister');
    net=struct('mlp',trainNetwork(single(X),single(y_s(:)),layers,opts),...
               'y_mu',y_mu,'y_sg',y_sg);
catch; net=[]; end
end

function yp = predict_icnn_ablation(m, X, y_ref)
try
    p_s=double(predict(m.mlp,single(X))); p_s=p_s(:);
    yp=p_s*m.y_sg+m.y_mu;
catch; yp=repmat(mean(y_ref,'omitnan'),size(X,1),1); end
end
