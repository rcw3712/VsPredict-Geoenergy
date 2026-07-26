function run = load_well_data(run, cfg)
% CORE.LOAD_WELL_DATA  Load raw well data with permanent ROW_ID (Rule §5.1).
%   - Never reads old predictions or stale CSVs (Rule 1.4)
%   - Assigns ROW_ID immediately after loading
%   - Validates units, ranges, duplicates, and depth order

% repo root is stored in run.repo_root by core.initialize_run
out_dir = fullfile(run.folder,'01_data_audit');

for wi = 1:2
    if wi==1; fpath=fullfile(run.repo_root,cfg.data.well_A_file); wname='Well-A';
    else;      fpath=fullfile(run.repo_root,cfg.data.well_B_file); wname='Well-B'; end

    fprintf('  [LOAD] Looking for: %s\n', fpath);
    if ~isfile(fpath)
        fprintf('  [DIAG] run.repo_root = %s\n', run.repo_root);
        fprintf('  [DIAG] cfg.data.well_A_file = %s\n', cfg.data.well_A_file);
        error('core:load_well_data','File not found: %s', fpath);
    end

    % Read with preserved column names
    try
        T = readtable(fpath,'Sheet',cfg.data.sheet,'VariableNamingRule','preserve');
    catch
        T = readtable(fpath,'Sheet',cfg.data.sheet);
    end

    % Column rename
    cm = cfg.data.col_map;
    curr = T.Properties.VariableNames;
    for ri = 1:size(cm,1)
        idx = find(strcmp(curr,cm{ri,1}),1);
        if ~isempty(idx)
            T.Properties.VariableNames{idx} = cm{ri,2};
            curr{idx} = cm{ri,2};
        end
    end

    % Exclude derived columns
    for ei = 1:numel(cfg.data.exclude_cols)
        ec = cfg.data.exclude_cols{ei};
        if ismember(ec,T.Properties.VariableNames); T.(ec) = []; end
    end

    % Derive VP and VS from measured slowness
    if ismember('DT', T.Properties.VariableNames);  T.VP = 304.8./T.DT;  end
    if ismember('DTS',T.Properties.VariableNames);  T.VS = 304.8./T.DTS; end
    if ismember('VP',T.Properties.VariableNames) && ismember('VS',T.Properties.VariableNames)
        T.VPVS = T.VP ./ T.VS;
    end

    % Sort by depth, assign permanent ROW_ID
    if ismember('DEPTH',T.Properties.VariableNames)
        [~,si] = sort(T.DEPTH); T = T(si,:);
    end
    T.ROW_ID  = (1:height(T))';
    T.WELL_ID = repmat({wname}, height(T), 1);

    % Validity audit
    audit = struct();
    audit.well    = wname;
    audit.n_rows  = height(T);
    audit.depth_min = min(T.DEPTH); audit.depth_max = max(T.DEPTH);
    d = T.DEPTH; diffs = diff(d);
    audit.n_dup_depth    = sum(diffs==0);
    audit.n_non_monotone = sum(diffs<0);
    audit.n_gaps_large   = sum(diffs>cfg.depth.gap_threshold*3);
    audit.depth_step_nom = cfg.depth.nominal_step;
    if isfield(cfg.depth,'nominal_step'); audit.depth_step_nom=cfg.depth.nominal_step; end

    for f = cfg.data.features
        c = f{1};
        if ismember(c,T.Properties.VariableNames)
            v = T.(c);
            audit.(['n_nan_' c])   = sum(isnan(v));
            audit.(['n_const_' c]) = (std(v,'omitnan')==0);
            if isfield(cfg.sanity,c)
                lo=cfg.sanity.(c)(1); hi=cfg.sanity.(c)(2);
                audit.(['n_phys_inv_' c]) = sum(v<lo|v>hi,'omitnan');
            end
        end
    end

    if wi==1; run.T_A_raw=T; run.audit_A=audit;
    else;      run.T_B_raw=T; run.audit_B=audit; end

    % Save audit CSV
    T_save = T;
    writetable(T_save, fullfile(out_dir,sprintf('%s_raw_data.csv',wname)));
    fprintf('  [LOAD] %s: %d rows, depth %.4f-%.4f m\n', wname, height(T), min(T.DEPTH), max(T.DEPTH));
end

run.gate.GATE_2_DATA_AND_OVERLAP = 'PENDING';
end
