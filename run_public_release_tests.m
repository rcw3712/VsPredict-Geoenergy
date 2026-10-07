function report = run_public_release_tests(project_root)
%RUN_PUBLIC_RELEASE_TESTS Self-contained checks for the public JAG archive.
% These tests do not require proprietary well logs or canonical pointer files.
if nargin < 1 || isempty(project_root)
    project_root = fileparts(mfilename('fullpath'));
end

addpath(genpath(project_root));
required = {
    fullfile(project_root,'JAG_ALIAS_MANIFEST.csv')
    fullfile(project_root,'JAG_RELEASE_MANIFEST_SHA256.csv')
    fullfile(project_root,'figures','jag-submission-20261007','FIGURE_MANIFEST_SHA256.csv')
    fullfile(project_root,'ajse_extension','selftest_ajse_icnn_comparator.m')
    };
assert(all(cellfun(@isfile,required)),'Public release is missing one or more required artifacts.');

data_root = fullfile(project_root,'data');
prohibited = [dir(fullfile(data_root,'**','*.xlsx')); ...
              dir(fullfile(data_root,'**','*.xls')); ...
              dir(fullfile(data_root,'**','*.las'))];
assert(isempty(prohibited),'Public data directory contains a prohibited proprietary input file.');

patch = selftest_ped_codex_patch_v3(project_root);
icnn = selftest_ajse_icnn_comparator(project_root);
report = struct('patch_status',patch.status, ...
                'icnn_pass',sum(icnn.PASS), ...
                'icnn_total',height(icnn), ...
                'public_inputs_absent',true, ...
                'status','PASS');
fprintf('JAG public-release self-test: PASS\n');
end
