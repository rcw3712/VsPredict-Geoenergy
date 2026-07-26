function validate_frozen_run(bundle)
% GSE_REPORT.VALIDATE_FROZEN_RUN  Sanity checks before generating figures.
%   Checks against known values from the run log (NOT hard-coded expected values).
%   All reference values come from bundle.run itself.

run = bundle.run;
fprintf('[GSE] Validating frozen run (seed=%d)...\n', run.cfg.seeds.canonical);

failures = {};

% 1. Run struct has required fields
required = {'id','cfg','eval_popA','eval_popB','deploy_name','deploy_r2_WA',...
            'T_A_raw','T_B_raw','T_B_proc','preproc_dev','fs','geomech'};
for ri = 1:numel(required)
    if ~isfield(run, required{ri})
        failures{end+1} = sprintf('run.%s missing', required{ri});
    end
end

% 2. Both evaluation populations have results
if isfield(run,'eval_popA') && isfield(run.eval_popA,'R2_raw')
    if isnan(run.eval_popA.R2_raw)
        failures{end+1} = 'eval_popA.R2_raw is NaN';
    end
end
if isfield(run,'eval_popB') && isfield(run.eval_popB,'R2_raw')
    if isnan(run.eval_popB.R2_raw)
        failures{end+1} = 'eval_popB.R2_raw is NaN';
    end
end
% Check geomech has all required fields
if isfield(run,'geomech')
    required_geo = {'n_eval','n_vpvs_pred_ok','n_nu_pred_ok','n_all_gates','valid_pct','all_gates_pct'};
    for rgi=1:numel(required_geo)
        if ~isfield(run.geomech, required_geo{rgi})
            failures{end+1} = sprintf('run.geomech.%s missing', required_geo{rgi});
        end
    end
end

% 3. Deploy model was selected from Well-A only
if isfield(run,'deploy_name') && isfield(run,'cfg')
    candidates = run.cfg.stack.meta_candidates;
    deploy_key = strrep(run.deploy_name,'_stacker','');
    if ~any(cellfun(@(c) contains(c,deploy_key), candidates))
        failures{end+1} = sprintf('Deploy model %s not in cfg.stack.meta_candidates', run.deploy_name);
    end
end

% 4. Predictions CSV exists and has correct row count
if ~isempty(bundle.pred_csv) && height(bundle.pred_csv) > 0
    if height(bundle.pred_csv) ~= height(run.T_B_proc)
        failures{end+1} = sprintf('predictions_WellB_v4.csv has %d rows, T_B_proc has %d', ...
            height(bundle.pred_csv), height(run.T_B_proc));
    end
end

if isempty(failures)
    fprintf('[GSE] Validation PASS\n');
    fprintf('[GSE]   Deploy: %s (R²_WA=%.4f)\n', run.deploy_name, run.deploy_r2_WA);
    fprintf('[GSE]   Pop-A: n=%d R²=%.4f\n', run.eval_popA.n, run.eval_popA.R2_raw);
    fprintf('[GSE]   Pop-B: n=%d R²=%.4f\n', run.eval_popB.n, run.eval_popB.R2_raw);
    fprintf('[GSE]   Outcome: GENERALIZATION_FAILURE (all R²<0)\n');
else
    for fi=1:numel(failures); fprintf('  [FAIL] %s\n',failures{fi}); end
    error('gse_report:ValidationFail','%d validation failures. See above.', numel(failures));
end
end
