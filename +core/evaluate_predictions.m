function run = evaluate_predictions(run, cfg)
% CORE.EVALUATE_PREDICTIONS  Blind evaluation on BOTH populations (Rule §8).
%   Well-B is opened here for the first time after deployment model is frozen.
%   Pop-A: all observed non-overlapping Seg0 (n=329)
%   Pop-B: + Vp/Vs physical QC gate (n=236)
%   Both populations use the SAME deployment model.
%   apply_vs_clipping called ONCE per prediction (Rule §7.4).

out_dir  = fullfile(run.folder,'06_predictions');
feat     = run.fs.S1_features;
dm       = run.deploy_model;
T_B_proc = run.T_B_proc;

% Evaluation masks (built in Gate 2, never recomputed)
pop_A    = logical(T_B_proc.POP_A_PRIMARY_BLIND);
pop_B    = logical(T_B_proc.POP_B_PHYSICAL_QC);
n_B_all  = height(T_B_proc);

%% Compute predictions on ALL Well-B rows
X_B = table2array(T_B_proc(:, feat)); X_B(isnan(X_B))=0;

% Base predictions
base_names = dm.base_order;
P_B = nan(n_B_all, numel(base_names));
for bi = 1:numel(base_names)
    nm = base_names{bi};
    P_B(:,bi) = core.predict_base_model(dm.base_models.(nm), X_B);
end
P_B(isnan(P_B))=0;

% Meta-features
ms_r = dm.meta_scaler_ridge; ms_h = dm.meta_scaler_hybrid;
OOF_B = (P_B - ms_r.mu) ./ ms_r.sg;

% Deployment model prediction
if strcmp(dm.deploy_name,'ridge_stacker') || contains(dm.deploy_name,'ridge')
    vs_pred_raw = [ones(n_B_all,1), OOF_B] * dm.coef;
else
    % For I-CNN / hybrid: predict via net
    X_hyb_B = table2array(T_B_proc(:,feat)); X_hyb_B(isnan(X_hyb_B))=0;
    Xm_hyb_B = ([X_hyb_B, P_B] - ms_h.mu) ./ ms_h.sg;
    if contains(dm.deploy_name,'hybrid')
        vs_pred_raw = predict_sequential(dm.net, Xm_hyb_B);
    else
        vs_pred_raw = predict_sequential(dm.net, OOF_B);
    end
end

%% Apply clipping ONCE (Rule §7.4)
[vs_pred_clipped, clip_info] = apply_vs_clipping_v4(vs_pred_raw, cfg.clip);

%% Evaluate on Pop-A and Pop-B
y_B    = T_B_proc.VS;
depth_B= T_B_proc.DEPTH;

run.eval_popA = evaluate_masked(y_B, vs_pred_raw, vs_pred_clipped, pop_A, depth_B, 'PopA_allObserved');
run.eval_popB = evaluate_masked(y_B, vs_pred_raw, vs_pred_clipped, pop_B, depth_B, 'PopB_physicalQC');
run.clip_info = clip_info;

% Report
fprintf('  [EVAL] Pop-A (n=%d): R2_raw=%.4f  RMSE_raw=%.4f  bias=%+.4f\n', ...
    run.eval_popA.n, run.eval_popA.R2_raw, run.eval_popA.RMSE_raw, run.eval_popA.bias_raw);
fprintf('  [EVAL] Pop-B (n=%d): R2_raw=%.4f  RMSE_raw=%.4f  bias=%+.4f\n', ...
    run.eval_popB.n, run.eval_popB.R2_raw, run.eval_popB.RMSE_raw, run.eval_popB.bias_raw);
fprintf('  [EVAL] Clipping: %d/%d rows (%.1f%%)\n', ...
    clip_info.n_clipped, n_B_all, clip_info.pct_clip);

% Compute empirical baseline predictions (on all Well-B rows)
vp_B = T_B_proc.VP;  % VP from raw — NOT z-scored (added in load_well_data)
if all(isnan(vp_B)); vp_B = run.T_B_raw.VP; end  % fallback to raw
C_CAST=[0.8042,-0.8559]; C_SH=[0.7700,-0.8674];
C_SA=[0.7936,-0.7868]; C_LI=[-0.05509,1.0168,-1.0305];
pred_castagna  = C_CAST(1)*vp_B  + C_CAST(2);
pred_gc_shale  = C_SH(1)*vp_B   + C_SH(2);
pred_gc_sand   = C_SA(1)*vp_B   + C_SA(2);
pred_gc_lime   = C_LI(1)*vp_B.^2+ C_LI(2)*vp_B + C_LI(3);
train_mean_vs  = mean(run.T_A_raw.VS(1:run.n_train),'omitnan');

% Save predictions CSV — ALL models
T_pred = table(T_B_proc.ROW_ID, depth_B, y_B, vs_pred_raw, vs_pred_clipped,...
    pop_A, pop_B,...
    pred_castagna, pred_gc_shale, pred_gc_sand, pred_gc_lime,...
    repmat(train_mean_vs, n_B_all, 1),...
    'VariableNames',{'ROW_ID','DEPTH','VS_measured','VS_pred_raw','VS_pred_clipped',...
    'POP_A_MASK','POP_B_MASK',...
    'Castagna_mudrock','GC_shale','GC_sand','GC_limestone','training_mean'});
T_pred.SEED        = repmat(cfg.seeds.canonical, n_B_all, 1);
T_pred.DEPLOY_MODEL= repmat({dm.deploy_name}, n_B_all, 1);
writetable(T_pred, fullfile(out_dir,'predictions_WellB_v4.csv'));

% Save TABLE7 for both populations
T7A = make_metrics_table(run.eval_popA, 'Pop-A (all observed, n=329)');
T7B = make_metrics_table(run.eval_popB, 'Pop-B (physical QC, n=236)');
writetable(T7A, fullfile(run.folder,'07_tables','TABLE7A_PopA_allObserved.csv'));
writetable(T7B, fullfile(run.folder,'07_tables','TABLE7B_PopB_physicalQC.csv'));

run.gate.GATE_12_BLIND_EVALUATION = 'PASS';
fprintf('  [EVAL] GATE_12 = PASS\n');
end

function m = evaluate_masked(y, y_raw, y_cl, mask, depth, label)
yt  = y(mask); yp_r = y_raw(mask); yp_c = y_cl(mask);
ok  = ~isnan(yt) & ~isnan(yp_r);
yto = yt(ok); yr  = yp_r(ok); yc  = yp_c(ok);
n   = sum(ok);
if n < 2
    m = struct('n',n,'R2_raw',-Inf,'RMSE_raw',Inf,'MAE_raw',Inf,'bias_raw',Inf,...
        'R2_clipped',-Inf,'RMSE_clipped',Inf,'label',label); return;
end
ss_tot = sum((yto-mean(yto)).^2);
m.n           = n;
m.R2_raw      = 1 - sum((yto-yr ).^2)/ss_tot;
m.RMSE_raw    = sqrt(mean((yto-yr ).^2));
m.MAE_raw     = mean(abs(yto-yr));
m.bias_raw    = mean(yr - yto);
m.R2_clipped  = 1 - sum((yto-yc ).^2)/ss_tot;
m.RMSE_clipped= sqrt(mean((yto-yc).^2));
m.bias_clipped= mean(yc - yto);
m.pearson     = corr(yto, yr);
m.std_ratio   = std(yr)/std(yto);
m.label       = label;
end

function [clipped, info] = apply_vs_clipping_v4(raw, clip_cfg)
info.vs_min = clip_cfg.vs_min; info.vs_max = clip_cfg.vs_max;
lo = raw < clip_cfg.vs_min; hi = raw > clip_cfg.vs_max;
clipped = raw; clipped(lo)=clip_cfg.vs_min; clipped(hi)=clip_cfg.vs_max;
info.n_low=sum(lo); info.n_high=sum(hi);
info.n_clipped=info.n_low+info.n_high; info.n_total=numel(raw);
info.pct_clip=info.n_clipped/info.n_total*100;
end

function pred = predict_sequential(net, X)
n=size(X,1); W=16; nc=size(X,2); ns=n-W+1;
if ns<=0; pred=nan(n,1); return; end
Xw=zeros(W,nc,1,ns,'single');
for j=1:ns; Xw(:,:,1,j)=single(X(j:j+W-1,:)); end
pw=squeeze(double(predict(net,Xw))); pw=pw(:);
pred=nan(n,1); half=floor(W/2);
for i=1:numel(pw); idx=i+half; if idx<=n; pred(idx)=pw(i); end; end
pred=fillmissing(pred,'nearest');
end

function T = make_metrics_table(m, pop_label)
T = table({pop_label},{m.n},{m.R2_raw},{m.RMSE_raw},{m.MAE_raw},{m.bias_raw},...
    {m.R2_clipped},{m.RMSE_clipped},...
    'VariableNames',{'Population','n','R2_raw','RMSE_raw','MAE_raw','bias_raw',...
    'R2_clipped','RMSE_clipped'});
end
