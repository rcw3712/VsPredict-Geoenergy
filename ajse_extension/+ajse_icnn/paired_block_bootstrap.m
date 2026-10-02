function T = paired_block_bootstrap(y, predictions, model_names, block_len, n_rep, seed)
% AJSE_ICNN.PAIRED_BLOCK_BOOTSTRAP  Paired moving-block metric differences.
%   Differences are comparator minus reference, where the first prediction
%   column is the corrected Ridge stacker reference.
y=double(y(:)); predictions=double(predictions);
assert(size(predictions,1)==numel(y) && size(predictions,2)==numel(model_names));
n=numel(y); assert(n>=block_len && block_len>=1);
rng(seed,'twister');
n_models=size(predictions,2);
delta_rmse=nan(n_rep,n_models-1); delta_mae=nan(n_rep,n_models-1);
for bi=1:n_rep
    idx=zeros(0,1);
    while numel(idx)<n
        s=randi(n-block_len+1);
        idx=[idx;(s:s+block_len-1)']; %#ok<AGROW>
    end
    idx=idx(1:n);
    yt=y(idx); ref=predictions(idx,1);
    rmse_ref=sqrt(mean((yt-ref).^2)); mae_ref=mean(abs(yt-ref));
    for mi=2:n_models
        yp=predictions(idx,mi);
        delta_rmse(bi,mi-1)=sqrt(mean((yt-yp).^2))-rmse_ref;
        delta_mae(bi,mi-1)=mean(abs(yt-yp))-mae_ref;
    end
end
rows=cell(n_models-1,8);
for mi=2:n_models
    dr=delta_rmse(:,mi-1); dm=delta_mae(:,mi-1);
    rows(mi-1,:)={string(model_names(mi)),string(model_names(1)), ...
        mean(dr),prctile(dr,2.5),prctile(dr,97.5), ...
        mean(dm),prctile(dm,2.5),prctile(dm,97.5)};
end
T=cell2table(rows,'VariableNames',{'COMPARATOR','REFERENCE', ...
    'DELTA_RMSE_MEAN','DELTA_RMSE_CI_LOW','DELTA_RMSE_CI_HIGH', ...
    'DELTA_MAE_MEAN','DELTA_MAE_CI_LOW','DELTA_MAE_CI_HIGH'});
end
