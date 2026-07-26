function test_no_hardcoded_metrics()
% Rule 1.6: No scientific results hard-coded in figure/caption/report code.
here = fileparts(fileparts(mfilename('fullpath')));
report_dirs = {fullfile(here,'+gse_report')};
% Values that should come from frozen bundle, not be in source code
forbidden_in_reports = {'-4\.99','-4\.925','0\.4272','0\.452','53\.6','7\.85','0\.4867'};
found = {};
for di = 1:numel(report_dirs)
    m_files = dir(fullfile(report_dirs{di},'*.m'));
    for fi = 1:numel(m_files)
        fp = fullfile(m_files(fi).folder,m_files(fi).name);
        content = fileread(fp);
        for pi = 1:numel(forbidden_in_reports)
            if ~isempty(regexp(content, forbidden_in_reports{pi},'once'))
                found{end+1} = sprintf('%s: %s',m_files(fi).name,forbidden_in_reports{pi}); %#ok<AGROW>
            end
        end
    end
end
if isempty(found)
    fprintf('[TEST] PASS test_no_hardcoded_metrics\n');
else
    fprintf('[TEST] FAIL — hard-coded metrics in report code:\n');
    for fi=1:numel(found); fprintf('  %s\n',found{fi}); end
    error('TestFail:HardcodedMetrics','%d violations',numel(found));
end
end
