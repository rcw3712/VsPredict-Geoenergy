function run = fit_preprocessor(run, cfg)
% CORE.FIT_PREPROCESSOR  Fit preprocessing parameters on training data.
%   Rule §7: Fold-local preprocessing; no validation leakage.
%   Creates DEVELOPMENT preprocessor (for OOF) and will later create
%   DEPLOYMENT preprocessor (on full Well-A, after model selection).
%   OOD values are FLAGGED, not imputed (Rule §7.3).

out_dir = fullfile(run.folder,'02_preprocessing');
T_A = run.T_A_raw;
feat = cfg.data.features;

% Development preprocessor: fit on training block only
tr_mask = T_A.SPLIT_FLAG;
T_tr = T_A(tr_mask,:);

pm = struct();
pm.features    = feat;
pm.fit_source  = 'Well-A development training block';
pm.fit_n_rows  = sum(tr_mask);
pm.fit_depth_min = min(T_tr.DEPTH);
pm.fit_depth_max = max(T_tr.DEPTH);
pm.fit_row_ids = T_A.ROW_ID(tr_mask);
pm.version     = '4.0';
pm.normalize   = cfg.preproc.normalize;

pm.scaler      = struct();
pm.iqr_bounds  = struct();
pm.imputation  = struct();

for fi = 1:numel(feat)
    f = feat{fi};
    if ~ismember(f,T_tr.Properties.VariableNames); continue; end
    v = T_tr.(f);
    ok = ~isnan(v);
    if ~isfield(cfg.sanity,f)
        lo=-Inf; hi=Inf;
    else
        lo=cfg.sanity.(f)(1); hi=cfg.sanity.(f)(2);
    end
    % Physical invalidity check (never mark OOD as invalid — Rule §7.2)
    phys_ok = v>=lo & v<=hi & ok;
    v_valid = v(phys_ok);

    pm.scaler.(f).mu = mean(v_valid);
    pm.scaler.(f).sg = std(v_valid); if pm.scaler.(f).sg==0; pm.scaler.(f).sg=1; end

    q1=quantile(v_valid,0.25); q3=quantile(v_valid,0.75); iqr_k=cfg.preproc.iqr_k;
    pm.iqr_bounds.(f).lo = q1 - iqr_k*(q3-q1);
    pm.iqr_bounds.(f).hi = q3 + iqr_k*(q3-q1);
    pm.iqr_bounds.(f).zscore_mu = pm.scaler.(f).mu;
    pm.iqr_bounds.(f).zscore_sg = pm.scaler.(f).sg;
    pm.imputation.(f).median = median(v_valid);
    pm.imputation.(f).n_valid = sum(phys_ok);
end

pm.hash = compute_pm_hash(pm);
save(fullfile(out_dir,'preprocessor_development.mat'),'pm','-v7.3');

run.preproc_dev = pm;
run.gate.GATE_4_PREPROCESSING = 'PENDING';
fprintf('  [PREPROC] Development preprocessor fitted (n=%d rows)\n', pm.fit_n_rows);
end

function h = compute_pm_hash(pm)
feat = pm.features;
parts = {sprintf('n=%d',pm.fit_n_rows)};
for fi=1:numel(feat)
    f=feat{fi};
    if isfield(pm.scaler,f)
        parts{end+1}=sprintf('%s:mu=%.6f,sg=%.6f',f,pm.scaler.(f).mu,pm.scaler.(f).sg); %#ok<AGROW>
    end
end
h = strjoin(parts,'|');
end
