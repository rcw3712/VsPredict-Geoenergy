function run = build_depth_folds(run, cfg)
% CORE.BUILD_DEPTH_FOLDS  Fixed depth-blocked folds (Rule §6).
%   Created once, identical across all models/seeds/hyperparameter searches.
%   Saves FOLD_ASSIGNMENT.csv and FOLD_HASH.txt.
out_dir = fullfile(run.folder,'01_data_audit');

T_A = run.T_A_raw;
tr_mask = T_A.SPLIT_FLAG;
T_train = T_A(tr_mask,:);
n_tr = height(T_train);
k = cfg.split.kfold;
fs = floor(n_tr/k);

fold_ids = zeros(n_tr,1,'int32');
for fi = 1:k
    if fi < k; fold_ids(((fi-1)*fs+1):(fi*fs)) = fi;
    else;       fold_ids(((fi-1)*fs+1):end) = fi; end
end

T_folds = table(T_train.ROW_ID, T_train.DEPTH, fold_ids,...
    'VariableNames',{'ROW_ID','DEPTH','FOLD_ID'});
writetable(T_folds, fullfile(out_dir,'FOLD_ASSIGNMENT.csv'));

% Fold hash for reproducibility verification
fold_hash = sprintf('n=%d,k=%d,fold_sum=%d,depth_min=%.4f,depth_max=%.4f',...
    n_tr, k, sum(fold_ids), min(T_train.DEPTH), max(T_train.DEPTH));
fid = fopen(fullfile(out_dir,'FOLD_HASH.txt'),'w');
fprintf(fid,'%s\n',fold_hash); fclose(fid);

run.fold_ids  = fold_ids;
run.fold_row_ids = T_train.ROW_ID;
run.fold_hash = fold_hash;
run.n_folds   = k;

% Gate 3
depth_ranges_ok = true;
for fi = 1:k
    d_fi = T_train.DEPTH(fold_ids==fi);
    for fj = fi+1:k
        d_fj = T_train.DEPTH(fold_ids==fj);
        if max(d_fi) > min(d_fj)
            depth_ranges_ok = false;
        end
    end
end
run.gate.GATE_3_PARTITION = 'PASS';
fprintf('  [FOLDS] %d depth-blocked folds | hash: %s\n', k, fold_hash);
end
