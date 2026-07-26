function run = standardize_columns(run, cfg)
% CORE.STANDARDIZE_COLUMNS  Verify column standardization after load_well_data.
%   Column renaming is done in load_well_data; this function verifies.
required = [cfg.data.features, {'DEPTH','VS','VP','DTS'}];
for wi = 1:2
    if wi==1; T=run.T_A_raw; wname='Well-A'; else; T=run.T_B_raw; wname='Well-B'; end
    for ri = 1:numel(required)
        c = required{ri};
        if ~ismember(c, T.Properties.VariableNames)
            warning('core:standardize_columns','%s missing in %s',c,wname);
        end
    end
end
fprintf('  [STD_COLS] Column standardization verified\n');
end
