function test_path_uniqueness()
% TEST_PATH_UNIQUENESS  Verify no addpath(genpath) is used. Rule 1.2.
here = fileparts(fileparts(mfilename('fullpath')));
m_files = dir(fullfile(here,'**','*.m'));
violations = {};
for fi = 1:numel(m_files)
    fp = fullfile(m_files(fi).folder, m_files(fi).name);
    content = fileread(fp);
    lines = strsplit(content,newline);
    for li = 1:numel(lines)
        l = strtrim(lines{li});
        if ~startsWith(l,'%') && contains(l,'addpath') && contains(l,'genpath')
            violations{end+1} = sprintf('%s:%d',m_files(fi).name,li); %#ok<AGROW>
        end
    end
end
if isempty(violations)
    fprintf('[TEST] PASS test_path_uniqueness\n');
else
    fprintf('[TEST] FAIL test_path_uniqueness — addpath(genpath) in:\n');
    for vi=1:numel(violations); fprintf('  %s\n',violations{vi}); end
    error('TestFail:PathUniqueness','%d addpath(genpath) violations',numel(violations));
end
end
