function run = define_data_roles(run, cfg)
% CORE.DEFINE_DATA_ROLES  Assign DATA_ROLE to every row (Rule §5.3).
%   Roles: WELL_A_DEVELOPMENT, WELL_A_INTERNAL_TEST,
%          WELL_B_SEG0_PRIMARY_BLIND, WELL_B_SEG1_OVERLAP_DIAGNOSTIC
%   Seg1 must never enter primary blind metrics.
%   Gate 2 passes only if overlap is excluded from Seg0.

out_dir = fullfile(run.folder,'01_data_audit');

% Determine depth boundaries dynamically from data + config
T_A = run.T_A_raw; T_B = run.T_B_raw;
n_A = height(T_A);
n_te = round(n_A * cfg.split.test_frac);
n_tr = n_A - n_te;
depth_boundary = T_A.DEPTH(n_tr);  % last training depth

% Well-A roles
T_A.DATA_ROLE = repmat({'WELL_A_DEVELOPMENT'}, n_A, 1);
T_A.DATA_ROLE(T_A.DEPTH > depth_boundary) = {'WELL_A_INTERNAL_TEST'};
T_A.SPLIT_FLAG = T_A.DEPTH <= depth_boundary;  % true=train, false=test
run.T_A_raw = T_A;
run.depth.wellA_train_max = depth_boundary;
run.depth.wellA_test_min  = T_A.DEPTH(n_tr+1);
run.n_train = n_tr; run.n_test = n_te;

% Well-B roles
seg0_max = cfg.depth.wellB_seg0_max;
seg1_min = cfg.depth.wellB_seg1_min;
n_B = height(T_B);
T_B.DATA_ROLE = repmat({'WELL_B_SEG0_PRIMARY_BLIND'}, n_B, 1);
T_B.DATA_ROLE(T_B.DEPTH > seg0_max) = {'WELL_B_SEG1_OVERLAP_DIAGNOSTIC'};
T_B.SEGMENT_ID = zeros(n_B,1,'int32');
T_B.SEGMENT_ID(T_B.DEPTH > seg0_max) = 1;

% Verify: no Seg1 rows should be non-duplicates
seg1_non_dup = T_B.SEGMENT_ID==1 & ~T_B.CROSSWELL_DUPLICATE;
if any(seg1_non_dup)
    warning('core:define_data_roles','%d Seg1 rows are NOT duplicates. Review overlap detection.', ...
        sum(seg1_non_dup));
end

run.T_B_raw = T_B;
run.depth.wellB_seg0_max = seg0_max;
run.depth.wellB_seg1_min = seg1_min;
run.n_seg0 = sum(T_B.SEGMENT_ID==0);
run.n_seg1 = sum(T_B.SEGMENT_ID==1);

% Build evaluation populations (Rule §8) — using measured data only
% Population A: Seg0 + observed VS
seg0 = T_B.SEGMENT_ID==0;
T_B.POP_A_PRIMARY_BLIND  = seg0 & ~isnan(T_B.VS) & ~isnan(T_B.VP);
% Population B: Pop A + measured Vp/Vs physical gate
vpvs_ok = T_B.VPVS >= cfg.sanity.vpvs_min & T_B.VPVS <= cfg.sanity.vpvs_max;
T_B.POP_B_PHYSICAL_QC   = T_B.POP_A_PRIMARY_BLIND & vpvs_ok;
run.T_B_raw = T_B;

run.n_pop_A = sum(T_B.POP_A_PRIMARY_BLIND);
run.n_pop_B = sum(T_B.POP_B_PHYSICAL_QC);

% Build EVALUATION_MASKS.csv
excl_reason = repmat({'IN_EVALUATION'}, n_B, 1);
excl_reason(T_B.SEGMENT_ID==1) = {'SEG1_OVERLAP'};
excl_reason(T_B.SEGMENT_ID==0 & isnan(T_B.VS)) = {'VS_MISSING'};
excl_reason(T_B.SEGMENT_ID==0 & ~isnan(T_B.VS) & isnan(T_B.VP)) = {'VP_MISSING'};
T_masks = table(T_B.ROW_ID, T_B.DEPTH, T_B.DATA_ROLE, T_B.SEGMENT_ID,...
    T_B.POP_A_PRIMARY_BLIND, T_B.POP_B_PHYSICAL_QC, excl_reason,...
    'VariableNames',{'ROW_ID','DEPTH','DATA_ROLE','SEGMENT_ID',...
    'PRIMARY_BLIND_MASK','PHYSICAL_QC_MASK','EXCLUSION_REASON'});
writetable(T_masks, fullfile(out_dir,'EVALUATION_MASKS.csv'));

% DATA_ROLE_MANIFEST.csv
all_T = [T_A(:,{'ROW_ID','WELL_ID','DEPTH','DATA_ROLE'});
         T_B(:,{'ROW_ID','WELL_ID','DEPTH','DATA_ROLE'})];
writetable(all_T, fullfile(out_dir,'DATA_ROLE_MANIFEST.csv'));

% GATE 2 pass conditions
gate2_pass = true;
gate2_fail_reasons = {};
if run.n_seg0 < 100; gate2_pass=false; gate2_fail_reasons{end+1}='Seg0 too small'; end
if run.overlap.n_overlap == 0; gate2_fail_reasons{end+1}='WARNING: no overlap detected (check data)'; end
if run.n_pop_A < 50; gate2_pass=false; gate2_fail_reasons{end+1}='Pop A too small'; end
if any(T_B.POP_A_PRIMARY_BLIND & T_B.CROSSWELL_DUPLICATE)
    gate2_pass=false; gate2_fail_reasons{end+1}='Duplicates in Pop A'; end

if gate2_pass
    run.gate.GATE_2_DATA_AND_OVERLAP = 'PASS';
else
    run.gate.GATE_2_DATA_AND_OVERLAP = sprintf('FAIL: %s', strjoin(gate2_fail_reasons,'; '));
end

fprintf('  [ROLES] Well-A: %d train, %d test\n', n_tr, n_te);
fprintf('  [ROLES] Well-B: %d Seg0 (%d Pop-A, %d Pop-B), %d Seg1\n', ...
    run.n_seg0, run.n_pop_A, run.n_pop_B, run.n_seg1);
fprintf('  [ROLES] GATE_2 = %s\n', run.gate.GATE_2_DATA_AND_OVERLAP);
end
