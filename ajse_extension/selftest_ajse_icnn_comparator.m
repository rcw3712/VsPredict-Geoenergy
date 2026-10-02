function report = selftest_ajse_icnn_comparator(project_root)
% SELFTEST_AJSE_ICNN_COMPARATOR  Fast structural and training smoke tests.
if nargin<1 || isempty(project_root)
    project_root=fileparts(fileparts(mfilename('fullpath')));
end
addpath(genpath(project_root));
checks=strings(0,1); passed=false(0,1);

record('fixed architecture is frozen',@() assert_hp());
record('missing segment IDs fail closed',@() assert_missing_segments());
record('cross-gap windows are discarded',@() assert_cross_gap());
record('round-trip prediction is finite',@() assert_smoke_train());

report=table(checks,passed,'VariableNames',{'CHECK','PASS'});
fprintf('AJSE I-CNN comparator self-test: %d/%d PASS\n',sum(passed),numel(passed));
assert(all(passed),'AJSE I-CNN comparator self-test failed');

    function record(name,fn)
        checks(end+1,1)=string(name); %#ok<AGROW>
        try
            fn(); passed(end+1,1)=true; %#ok<AGROW>
            fprintf('[PASS] %s\n',name);
        catch ME
            passed(end+1,1)=false; %#ok<AGROW>
            fprintf('[FAIL] %s: %s\n',name,ME.message);
        end
    end
end

function assert_hp()
hp=ajse_icnn.fixed_hp(200);
assert(isequal(hp.kernels,[3 5 7]) && hp.filters==32 && ...
    hp.lr==1e-4 && hp.window==16 && ~hp.wellB_used_for_tuning);
end

function assert_missing_segments()
X=randn(40,4); y=randn(40,1); hp=ajse_icnn.fixed_hp(1);
failed=false;
try; ajse_icnn.fit_model(X,y,hp,1,[],'icnn');
catch ME; failed=strcmp(ME.identifier,'ajse_icnn:MissingSegments'); end
assert(failed,'Missing segments did not fail closed');
end

function assert_cross_gap()
rng(1); X=randn(48,4); y=randn(48,1); seg=[ones(24,1);2*ones(24,1)];
hp=ajse_icnn.fixed_hp(1);
m=ajse_icnn.fit_model(X,y,hp,1,seg,'icnn_test');
assert(m.n_discarded_cross_segment==15 && m.n_retained_cross_segment==0);
end

function assert_smoke_train()
rng(2); X=randn(64,4); y=2+0.1*X(:,1)-0.05*X(:,2);
hp=ajse_icnn.fixed_hp(2);
m=ajse_icnn.fit_model(X,y,hp,2,ones(64,1),'icnn_test');
[yp,a]=ajse_icnn.predict_model(m,X,ones(64,1));
assert(all(isfinite(yp)) && a.N_RETAINED_CROSS_SEGMENT==0);
end
