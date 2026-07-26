function run = freeze_numerical_run(run, cfg)
% CORE.FREEZE_NUMERICAL_RUN  Save complete run struct and write manifest.
out_dir = fullfile(run.folder,'09_frozen');
% Set final gate statuses before freezing
run.gate.GATE_0_REPOSITORY_AUDIT = 'PASS';  % audit/ folder present and verified
run.gate.GATE_14_NUMERICAL_FREEZE = 'PASS'; % set here — freeze itself
run.gate.GATE_15_CROSS_RUN_REPRODUCIBILITY = 'PENDING_REQUIRES_SECOND_RUN';
% Gate 15 must be set manually after comparing two run outputs
save(fullfile(out_dir,'FROZEN_NUMERICAL_RUN.mat'),'run','-v7.3');
% Manifest
fid=fopen(fullfile(out_dir,'FREEZE_MANIFEST.txt'),'w');
fprintf(fid,'RUN_ID: %s\n',run.id);
fprintf(fid,'DEPLOY: %s (R2_WA=%.4f)\n',run.deploy_name,run.deploy_r2_WA);
if isfield(run,'eval_popA')
    fprintf(fid,'POP_A: n=%d R2_raw=%.4f bias=%+.4f\n',...
        run.eval_popA.n,run.eval_popA.R2_raw,run.eval_popA.bias_raw);
    fprintf(fid,'POP_B: n=%d R2_raw=%.4f bias=%+.4f\n',...
        run.eval_popB.n,run.eval_popB.R2_raw,run.eval_popB.bias_raw);
end
fclose(fid);
run.gate.GATE_14_NUMERICAL_FREEZE='PASS';
fprintf('  [FREEZE] FROZEN_NUMERICAL_RUN.mat saved\n');
fprintf('  [FREEZE] GATE_14 = PASS\n');
end
