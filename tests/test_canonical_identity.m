function test_canonical_identity(run)
% TEST_CANONICAL_IDENTITY  Canonical = seed_results{seed==canonical_seed}.
% Rule §17: No separate canonical retraining.
if ~isfield(run,'seed_results') || ~isfield(run,'canonical')
    fprintf('[TEST] SKIP test_canonical_identity — no multi-seed results yet\n'); return;
end
canonical_seed = run.cfg.seeds.canonical;
can_idx = find([run.seed_results.seed] == canonical_seed, 1);
if isempty(can_idx)
    error('TestFail:CanonicalIdentity','Canonical seed %d not in seed_results',canonical_seed);
end
% Compare key fields
fields_to_check = {'R2_blind_popA','RMSE_blind_popA','deploy_model'};
for fi=1:numel(fields_to_check)
    f=fields_to_check{fi};
    if isfield(run.canonical,f) && isfield(run.seed_results(can_idx),f)
        v_can   = run.canonical.(f);
        v_seedr = run.seed_results(can_idx).(f);
        if isnumeric(v_can) && abs(v_can-v_seedr)>1e-10
            error('TestFail:CanonicalIdentity','%s differs: canonical=%.6f seed_result=%.6f',f,v_can,v_seedr);
        elseif ischar(v_can) && ~strcmp(v_can,v_seedr)
            error('TestFail:CanonicalIdentity','%s differs: canonical=%s seed_result=%s',f,v_can,v_seedr);
        end
    end
end
fprintf('[TEST] PASS test_canonical_identity\n');
end
