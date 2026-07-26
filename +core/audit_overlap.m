function run = audit_overlap(run, cfg)
% CORE.AUDIT_OVERLAP  Detect cross-well duplicate rows (Rule §5.3).
%   Outputs OVERLAP_REPORT.csv, OVERLAP_MATCHED_ROWS.csv, DATA_ROLE_MANIFEST.csv

out_dir = fullfile(run.folder,'01_data_audit');
T_A = run.T_A_raw; T_B = run.T_B_raw;
tol = 1e-6;
feat_check = [cfg.data.features, {'DTS'}];
feat_check = intersect(feat_check, T_A.Properties.VariableNames, 'stable');
feat_check = intersect(feat_check, T_B.Properties.VariableNames, 'stable');

n_B = height(T_B);
T_B.CROSSWELL_DUPLICATE = false(n_B,1);
T_B.MATCHED_ROW_ID_A    = zeros(n_B,1,'int32');

n_dup = 0; matched_rows = [];
for bi = 1:n_B
    d_b = T_B.DEPTH(bi);
    ai  = find(abs(T_A.DEPTH - d_b) < tol, 1);
    if isempty(ai); continue; end
    is_dup = true;
    for fc = feat_check
        c = fc{1};
        if abs(T_B.(c)(bi) - T_A.(c)(ai)) > tol; is_dup=false; break; end
    end
    if is_dup
        T_B.CROSSWELL_DUPLICATE(bi) = true;
        T_B.MATCHED_ROW_ID_A(bi)   = int32(T_A.ROW_ID(ai));
        n_dup = n_dup + 1;
        matched_rows(end+1,:) = [T_B.ROW_ID(bi), T_A.ROW_ID(ai), T_B.DEPTH(bi)]; %#ok<AGROW>
    end
end

run.T_B_raw = T_B;
run.overlap.n_overlap = n_dup;
run.overlap.n_wellB   = n_B;
run.overlap.pct_overlap = n_dup/n_B*100;
if n_dup>0
    dup_depths = T_B.DEPTH(T_B.CROSSWELL_DUPLICATE);
    run.overlap.depth_min = min(dup_depths);
    run.overlap.depth_max = max(dup_depths);
else
    run.overlap.depth_min = NaN;
    run.overlap.depth_max = NaN;
end

% Save OVERLAP_REPORT.csv
T_ov = struct2table(run.overlap);
writetable(T_ov, fullfile(out_dir,'OVERLAP_REPORT.csv'));

% Save OVERLAP_MATCHED_ROWS.csv
if ~isempty(matched_rows)
    T_match = array2table(matched_rows,'VariableNames',{'ROW_ID_B','ROW_ID_A','DEPTH'});
    writetable(T_match, fullfile(out_dir,'OVERLAP_MATCHED_ROWS.csv'));
end

fprintf('  [OVERLAP] %d/%d Well-B rows (%.1f%%) are cross-well duplicates\n', ...
    n_dup, n_B, run.overlap.pct_overlap);
fprintf('  [OVERLAP] Seg1 will be excluded from primary blind evaluation\n');
end
