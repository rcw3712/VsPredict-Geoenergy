function test_no_duplicate_active_functions()
here = fileparts(fileparts(mfilename('fullpath')));
from_root = dir(fullfile(here,'**','*.m'));
func_files = struct();
dups = {};
for fi = 1:numel(from_root)
    fname = strrep(from_root(fi).name,'.m','');
    if isfield(func_files,fname)
        existing = func_files.(fname);
        rel1 = strrep(fullfile(from_root(fi).folder,from_root(fi).name),here,'');
        if ~strcmp(rel1,existing)
            dups{end+1} = sprintf('%s: %s vs %s',fname,existing,rel1); %#ok<AGROW>
        end
    else
        func_files.(fname) = strrep(fullfile(from_root(fi).folder,from_root(fi).name),here,'');
    end
end
if isempty(dups)
    fprintf('[TEST] PASS test_no_duplicate_active_functions\n');
else
    fprintf('[TEST] FAIL — duplicate function names:\n');
    for di=1:numel(dups); fprintf('  %s\n',dups{di}); end
    error('TestFail:Duplicates','%d duplicate function names',numel(dups));
end
end
