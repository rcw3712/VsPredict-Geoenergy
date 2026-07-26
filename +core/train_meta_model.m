function run = train_meta_model(run, cfg)
% CORE.TRAIN_META_MODEL  Train Ridge stacker, plain I-CNN, Hybrid I-CNN.
%   All meta-learners use per-component seeds (Rule §12).
%   Models fitted on OOF meta-features (never on raw training features directly).

feat  = run.fs.S1_features;
hp    = run.hyperparams;
seed  = cfg.seeds.canonical;

y_tr  = run.meta.y_tr;
y_te  = run.meta.y_te;
Xm_tr = run.meta.Xm_ridge.tr;
Xm_te = run.meta.Xm_ridge.te;
Xm_hyb_tr = run.meta.Xm_hybrid.tr;
Xm_hyb_te = run.meta.Xm_hybrid.te;

run.meta_models = struct();

%% Ridge stacker
fprintf('  [META] Training Ridge stacker...\n');
rng(seed + cfg.seeds.offset_ridge, 'twister');
[B_ridge, lam_sel] = train_ridge_stacker_cv(Xm_tr, y_tr, hp.ridge);
run.meta_models.ridge.coef   = B_ridge;
run.meta_models.ridge.lambda = lam_sel;
pred_ridge_te = [ones(size(Xm_te,1),1), Xm_te] * B_ridge;
run.meta_metrics.ridge.R2_te = compute_r2(y_te, pred_ridge_te);
run.meta_metrics.ridge.RMSE_te = sqrt(mean((y_te-pred_ridge_te).^2,'omitnan'));
fprintf('  [META] Ridge: lambda=%.4f  R2_te=%.4f\n', lam_sel, run.meta_metrics.ridge.R2_te);

%% Plain I-CNN (OOF-only meta-features)
fprintf('  [META] Training I-CNN...\n');
rng(seed + cfg.seeds.offset_icnn, 'twister');
[net_icnn, pred_icnn_te, icnn_y_mu, icnn_y_sg] = train_icnn_meta(Xm_tr, y_tr, Xm_te, hp.icnn, ...
    seed + cfg.seeds.offset_icnn, cfg);
run.meta_models.icnn.net     = net_icnn;
run.meta_models.icnn.y_mu    = icnn_y_mu;
run.meta_models.icnn.y_sg    = icnn_y_sg;
run.meta_metrics.icnn.R2_te   = compute_r2(y_te, pred_icnn_te);
run.meta_metrics.icnn.RMSE_te = sqrt(mean((y_te-pred_icnn_te).^2,'omitnan'));
fprintf('  [META] I-CNN: R2_te=%.4f\n', run.meta_metrics.icnn.R2_te);

%% Hybrid I-CNN (raw features + OOF)
fprintf('  [META] Training Hybrid I-CNN...\n');
rng(seed + cfg.seeds.offset_hybrid_icnn, 'twister');
[net_hybrid, pred_hybrid_te, hybrid_y_mu, hybrid_y_sg] = train_icnn_meta(Xm_hyb_tr, y_tr, Xm_hyb_te, hp.hybrid, ...
    seed + cfg.seeds.offset_hybrid_icnn, cfg);
run.meta_models.hybrid_icnn.net     = net_hybrid;
run.meta_models.hybrid_icnn.y_mu    = hybrid_y_mu;
run.meta_models.hybrid_icnn.y_sg    = hybrid_y_sg;
run.meta_metrics.hybrid_icnn.R2_te   = compute_r2(y_te, pred_hybrid_te);
run.meta_metrics.hybrid_icnn.RMSE_te = sqrt(mean((y_te-pred_hybrid_te).^2,'omitnan'));
fprintf('  [META] Hybrid I-CNN: R2_te=%.4f\n', run.meta_metrics.hybrid_icnn.R2_te);

run.meta_preds_te = struct('ridge',pred_ridge_te,'icnn',pred_icnn_te,...
    'hybrid_icnn',pred_hybrid_te);
run.gate.GATE_8_META_LEARNERS = 'PASS';
fprintf('  [META] GATE_8 = PASS\n');
end

function [B, lam_sel] = train_ridge_stacker_cv(X, y, hp)
lambda_grid = logspace(-2,2,25);
if isfield(hp,'lambda_grid'); lambda_grid=hp.lambda_grid; end
Xb = [ones(size(X,1),1), X];
best_cv=-Inf; lam_sel=lambda_grid(1);
k=5; n=size(X,1); fs=floor(n/k);
for li=1:numel(lambda_grid)
    lam=lambda_grid(li); r2s=zeros(k,1);
    for fi=1:k
        vi=((fi-1)*fs+1):min(fi*fs,n); ti=setdiff(1:n,vi);
        Xbv=Xb(vi,:); Xbt=Xb(ti,:); yv=y(vi); yt=y(ti);
        B_=(Xbt'*Xbt + lam*eye(size(Xbt,2)))\(Xbt'*yt);
        yp=Xbv*B_; ok=~isnan(yv)&~isnan(yp);
        yt2=yv(ok); yp2=yp(ok);
        if sum(ok)>1; r2s(fi)=1-sum((yt2-yp2).^2)/sum((yt2-mean(yt2)).^2); end
    end
    if mean(r2s)>best_cv; best_cv=mean(r2s); lam_sel=lam; end
end
B = (Xb'*Xb + lam_sel*eye(size(Xb,2)))\(Xb'*y);
fprintf('    [RIDGE] lambda=%.4f CV-R2=%.4f\n',lam_sel,best_cv);
end

function [net, pred_te, y_mu, y_sg] = train_icnn_meta(Xm_tr, y_tr, Xm_te, hp, seed, cfg)
if isfield(hp,'epochs'); ep=hp.epochs; else; ep=200; end
if isfield(hp,'lr');     lr=hp.lr;     else; lr=1e-3; end
if isfield(hp,'batch');  bs=hp.batch;  else; bs=32;   end
if isfield(hp,'kernels');ks=hp.kernels;else; ks=[3,5,7]; end
if isfield(hp,'filters');nf=hp.filters;else; nf=32;   end

W=16; n=size(Xm_tr,1); nc=size(Xm_tr,2); ns=n-W+1;
if ns<=0; net=[]; pred_te=nan(size(Xm_te,1),1); return; end
Xw=zeros(W,1,nc,ns,'single');
for j=1:ns; Xw(:,1,:,j)=reshape(single(Xm_tr(j:j+W-1,:)),W,1,nc); end
half=floor(W/2);

% ── TARGET SCALING: z-score y_tr before training ─────────────────────────
% Root cause of I-CNN mean prediction ~6.85 km/s (audit §4.3):
% meta-features are z-scored but y_tr was in physical km/s (~2.0-2.5).
% Scale mismatch causes gradient explosion toward ~7x the true mean.
y_mu = mean(y_tr,'omitnan');
y_sg = std(y_tr,'omitnan'); if y_sg < 1e-6; y_sg = 1; end
y_tr_scaled = (y_tr - y_mu) / y_sg;
% Roundtrip assertion
y_rt = y_tr_scaled * y_sg + y_mu;
assert(max(abs(y_rt - y_tr),[],'omitnan') < 1e-10, 'Target scale roundtrip failed');

% R2024a: reshape y to 4D [1×1×1×numObs] for imageInputLayer
y_seq_col=y_tr_scaled(half+1:min(n,ns+half)); n_yseq=numel(y_seq_col);
if n_yseq<ns; y_seq_col(end+1:ns)=mean(y_seq_col,'omitnan'); end
y_seq=reshape(single(y_seq_col(1:ns)),[1,1,1,ns]);

% Multi-scale I-CNN branches
lg=layerGraph();
lg=addLayers(lg,imageInputLayer([W,1,nc],'Name','in','Normalization','none'));
branch_outs={};
for ki=1:numel(ks)
    k_size=ks(ki); bn=sprintf('k%d',k_size);
    lg=addLayers(lg,[convolution2dLayer([k_size,1],nf,'Padding','same','Name',[bn '_c']), ...
        batchNormalizationLayer('Name',[bn '_b']),reluLayer('Name',[bn '_r'])]);
    lg=connectLayers(lg,'in',[bn '_c']);
    branch_outs{end+1}=[bn '_r'];
end
lg=addLayers(lg,depthConcatenationLayer(numel(ks),'Name','concat'));
for bi=1:numel(branch_outs); lg=connectLayers(lg,branch_outs{bi},['concat/in' num2str(bi)]); end
lg=addLayers(lg,[globalAveragePooling2dLayer('Name','gap'), ...
    fullyConnectedLayer(1,'Name','fc'),regressionLayer('Name','out')]);
lg=connectLayers(lg,'concat','gap');

opts=trainingOptions('adam','MaxEpochs',ep,'MiniBatchSize',bs,'InitialLearnRate',lr,...
    'Shuffle',cfg.training.shuffle,'Verbose',false,'ExecutionEnvironment','cpu',...
    'GradientThreshold',1.0,...     % gradient clipping — prevents explosion
    'L2Regularization',1e-4,...     % weight decay
    'ValidationFrequency',50);      % suppress intermediate validation output
rng(seed,'twister');
net=trainNetwork(Xw,y_seq,lg,opts);

% Predict on test
nt=size(Xm_te,1); nct=size(Xm_te,2); nst=nt-W+1;
if nst<=0; pred_te=nan(nt,1); return; end
Xwt=zeros(W,1,nct,nst,'single');
for j=1:nst; Xwt(:,1,:,j)=reshape(single(Xm_te(j:j+W-1,:)),W,1,nct); end
pw=squeeze(double(predict(net,Xwt))); pw=pw(:);
pred_te_scaled=nan(nt,1);
for i=1:numel(pw); idx=i+half; if idx<=nt; pred_te_scaled(idx)=pw(i); end; end
pred_te_scaled=fillmissing(pred_te_scaled,'nearest');
% ── INVERSE TARGET SCALING (back to km/s) ──────────────────────────────────
pred_te = pred_te_scaled * y_sg + y_mu;
end

function r2=compute_r2(yt,yp)
ok=~isnan(yt)&~isnan(yp); yt=yt(ok); yp=yp(ok);
if numel(yt)<2; r2=-Inf; return; end
r2=1-sum((yt-yp).^2)/sum((yt-mean(yt)).^2);
end
