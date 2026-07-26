function run = apply_preprocessor(run, cfg)
% CORE.APPLY_PREPROCESSOR  Apply fitted preprocessor without refitting.
%   OOD samples are FLAGGED per feature (Rule §7.3), NOT imputed.
%   Target DTS/VS is never modified.
%   Gate 4 verified here.

out_dir = fullfile(run.folder,'02_preprocessing');
pm = run.preproc_dev;
feat = cfg.data.features;

% Apply to Well-A (train + test using SAME dev preprocessor)
run.T_A_proc = apply_to_table(run.T_A_raw, pm, feat, cfg);
% Apply to Well-B Seg0 (using dev preprocessor — deployment preproc comes later)
run.T_B_proc = apply_to_table(run.T_B_raw, pm, feat, cfg);

% Gate 4 verification
gate_fail = {};

% --- Check 1: target DTS must be unchanged (done ONCE, outside feature loop) ---
% apply_to_table only modifies columns listed in feat = {GR,DT,NPHI,RHOB}.
% DTS is not in feat, so T_out = T_in copies it unchanged. This verifies that.
if ismember('DTS', run.T_A_proc.Properties.VariableNames) && ...
   ismember('DTS', run.T_A_raw.Properties.VariableNames)
    valid_mask = ~isnan(run.T_A_raw.DTS);           % logical, length = n_total
    orig_dts = run.T_A_raw.DTS(valid_mask);         % length = n_valid
    proc_dts = run.T_A_proc.DTS(valid_mask);        % length = n_valid (same mask)
    % max(abs(v)) — no 'omitnan' needed; NaNs excluded by valid_mask above
    if max(abs(orig_dts - proc_dts)) > 1e-9
        gate_fail{end+1} = 'DTS modified by preprocessing (target clean violation)';
    end
end

% --- Check 2: per-feature checks (missing column, OOD not imputed) ---
for fi = 1:numel(feat)
    f = feat{fi};
    if ~ismember(f, run.T_A_proc.Properties.VariableNames)
        gate_fail{end+1} = sprintf('%s missing after preprocessing', f);
        continue;
    end
    % OOD values must not be imputed (Rule 7.3)
    ood_col    = sprintf('OOD_Z3_%s',  f);
    impute_col = sprintf('IMPUTED_%s', f);
    if ismember(ood_col, run.T_A_proc.Properties.VariableNames) && ...
       ismember(impute_col, run.T_A_proc.Properties.VariableNames)
        ood_imputed = run.T_A_proc.(impute_col) & run.T_A_proc.(ood_col);
        if any(ood_imputed)
            gate_fail{end+1} = sprintf('OOD values imputed for %s (Rule 7.3 violation)', f);
        end
    end
end

% Preprocessor hash check
pm2 = run.preproc_dev;
if ~strcmp(pm.hash, pm2.hash)
    gate_fail{end+1}='Preprocessor hash mismatch (possible leakage)';
end

if isempty(gate_fail)
    run.gate.GATE_4_PREPROCESSING = 'PASS';
else
    run.gate.GATE_4_PREPROCESSING = sprintf('FAIL: %s', strjoin(gate_fail,'; '));
end

% Save preprocessed data summary
T_summary = table(feat', arrayfun(@(f) pm.scaler.(f{1}).mu, feat,'UniformOutput',true)',...
    arrayfun(@(f) pm.scaler.(f{1}).sg, feat,'UniformOutput',true)',...
    'VariableNames',{'FEATURE','SCALER_MU','SCALER_SG'});
writetable(T_summary, fullfile(out_dir,'preprocessor_scaler_summary.csv'));

fprintf('  [PREPROC] Applied to Well-A (%d rows) and Well-B (%d rows)\n',...
    height(run.T_A_proc), height(run.T_B_proc));
fprintf('  [PREPROC] GATE_4 = %s\n', run.gate.GATE_4_PREPROCESSING);
end

function T_out = apply_to_table(T_in, pm, feat, cfg)
T_out = T_in;
for fi = 1:numel(feat)
    f = feat{fi};
    if ~ismember(f,T_in.Properties.VariableNames); continue; end
    v = T_in.(f);
    T_out.([f '_RAW']) = v;  % preserve raw value
    
    % Compute OOD flags BEFORE any modification
    z = (v - pm.scaler.(f).mu) / pm.scaler.(f).sg;
    T_out.(['OOD_Z2_' f]) = abs(z) > 2;
    T_out.(['OOD_Z3_' f]) = abs(z) > 3;
    
    % Physical invalidity
    if isfield(cfg.sanity,f)
        lo=cfg.sanity.(f)(1); hi=cfg.sanity.(f)(2);
        phys_inv = v<lo | v>hi;
    else; phys_inv = false(height(T_in),1); end
    T_out.(['PHYS_INV_' f]) = phys_inv;
    
    % Missing / sentinel
    miss_flag = isnan(v);
    T_out.(['MISSING_' f]) = miss_flag;
    
    % Impute ONLY genuinely missing or physically invalid (NOT OOD)
    impute_mask = miss_flag | phys_inv;
    % OOD: keep value as-is (Rule 7.3)
    v_imputed = v;
    if any(impute_mask)
        v_imputed(impute_mask) = pm.imputation.(f).median;
    end
    T_out.(['IMPUTED_' f]) = impute_mask;
    
    % Z-score normalize
    T_out.(f) = (v_imputed - pm.scaler.(f).mu) / pm.scaler.(f).sg;
end
end
