function result = run_single_seed_deployment(T_A_raw, T_B_raw, feat, hp, seed, cfg, pm_full)
% CORE.RUN_SINGLE_SEED_DEPLOYMENT  Authoritative deployment procedure (single seed).
%   Used by BOTH freeze_deployment (Gate 11) and run_multiseed (Gate 10).
%   This guarantees identical procedure — differences come only from seed.
%
%   Inputs:
%     T_A_raw  — full Well-A raw table (492 rows)
%     T_B_raw  — full Well-B raw table (492 rows)
%     feat     — feature names cell array
%     hp       — frozen hyperparameters struct
%     seed     — RNG seed
%     cfg      — configuration
%     pm_full  — preprocessor fitted on full Well-A (required)
%   Output: result struct with predictions and metrics

ok_A = ~isnan(T_A_raw.VS);
X_A  = apply_pm_raw_inner(T_A_raw(ok_A,:), feat, pm_full);
y_A  = T_A_raw.VS(ok_A);
n_A  = sum(ok_A);
k    = cfg.split.kfold;

% Refit base models
base_names = cfg.stack.base_order;
base_models = struct();
for bi = 1:numel(base_names)
    nm  = base_names{bi};
    off = cfg.seeds.(['offset_' nm]);
    m_seed = seed + off + cfg.seeds.offset_refit;
    rng(m_seed,'twister');
    hp_b = get_hp_inner(hp, nm);
    base_models.(nm) = models.fit_base(X_A, y_A, nm, hp_b, m_seed, cfg);
end

% OOF on full Well-A for meta-features
fold_ids_A = make_folds_inner(n_A, k);
OOF_A = nan(n_A, numel(base_names));
for fi = 1:k
    val_m=fold_ids_A==fi; tr_m=~val_m;
    X_va=X_A(val_m,:); X_tr_fi=X_A(tr_m,:); y_tr_fi=y_A(tr_m);
    for bi=1:numel(base_names)
        nm=base_names{bi}; off=cfg.seeds.(['offset_' nm]);
        m_fi=seed+off+fi*cfg.seeds.offset_fold_mult+cfg.seeds.offset_refit;
        rng(m_fi,'twister');
        hp_b=get_hp_inner(hp,nm);
        m_fi_mdl=models.fit_base(X_tr_fi,y_tr_fi,nm,hp_b,m_fi,cfg);
        OOF_A(val_m,bi)=core.predict_base_model(m_fi_mdl,X_va);
    end
end
OOF_A(isnan(OOF_A))=0;

% Ridge meta-learner
ms_mu  = mean(OOF_A,1,'omitnan');
ms_sg  = std(OOF_A,0,1,'omitnan'); ms_sg(ms_sg<1e-6)=1;
Xm_A   = (OOF_A - ms_mu) ./ ms_sg;
Xb_A   = [ones(n_A,1), Xm_A];
lambda = hp.ridge.lambda_grid(ceil(numel(hp.ridge.lambda_grid)/2));
if isfield(hp,'ridge_lambda_selected'); lambda=hp.ridge_lambda_selected; end
rng(seed+cfg.seeds.offset_ridge+cfg.seeds.offset_refit,'twister');
B      = (Xb_A'*Xb_A + lambda*eye(size(Xb_A,2))) \ (Xb_A'*y_A);

% Predict on Well-B
X_B_all = apply_pm_raw_inner(T_B_raw, feat, pm_full);
P_B = nan(height(T_B_raw), numel(base_names));
for bi=1:numel(base_names)
    nm=base_names{bi};
    P_B(:,bi)=core.predict_base_model(base_models.(nm), X_B_all);
end
P_B(isnan(P_B))=0;
OOF_B_sc = (P_B - ms_mu) ./ ms_sg;
vs_pred  = [ones(height(T_B_raw),1), OOF_B_sc] * B;
vs_pred  = max(cfg.clip.vs_min, min(cfg.clip.vs_max, vs_pred));

% Evaluate
pop_A = logical(T_B_raw.POP_A_PRIMARY_BLIND);
pop_B = logical(T_B_raw.POP_B_PHYSICAL_QC);
result.seed       = seed;
result.vs_pred    = vs_pred;
result.base_models= base_models;
result.meta_coef  = B;
result.meta_scaler= struct('mu',ms_mu,'sg',ms_sg);
result.lambda     = lambda;
result.popA = eval_mask_inner(T_B_raw.VS, vs_pred, pop_A);
result.popB = eval_mask_inner(T_B_raw.VS, vs_pred, pop_B);
end

function m=eval_mask_inner(yt,yp,mask)
yt=yt(mask); yp=yp(mask); ok=~isnan(yt)&~isnan(yp); m.n=sum(ok);
yt=yt(ok); yp=yp(ok);
if m.n<2; m.r2=-Inf; m.rmse=Inf; m.bias=Inf; return; end
m.r2=1-sum((yt-yp).^2)/sum((yt-mean(yt)).^2);
m.rmse=sqrt(mean((yt-yp).^2)); m.bias=mean(yp-yt);
end

function X=apply_pm_raw_inner(T,feat,pm)
X=zeros(height(T),numel(feat));
for fi=1:numel(feat); f=feat{fi};
    if ~ismember(f,T.Properties.VariableNames)||~isfield(pm.scaler,f); continue; end
    v=T.(f); miss=isnan(v);
    if any(miss)&&isfield(pm.imputation,f); v(miss)=pm.imputation.(f).median; end
    X(:,fi)=(v-pm.scaler.(f).mu)/pm.scaler.(f).sg;
end; end

function hp_b=get_hp_inner(hp,nm); if isfield(hp,nm); hp_b=hp.(nm); else; hp_b=struct(); end; end

function fids=make_folds_inner(n,k)
fs=floor(n/k); fids=zeros(n,1,'int32');
for fi=1:k; if fi<k; fids((fi-1)*fs+1:fi*fs)=fi; else; fids((fi-1)*fs+1:end)=fi; end; end
end
