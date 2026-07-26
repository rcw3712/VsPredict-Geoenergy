function pred = predict_base_model(model, X_new)
% CORE.PREDICT_BASE_MODEL  Apply fitted base model. Separated from fit (Rule 10.4).
switch lower(model.type)
    case 'pnn'
        pred = predict_pnn(model, X_new);
    case {'mlffnn','dffnn'}
        % R2024a: input format matches training (numObs × numFeatures, no transpose)
        raw  = predict(model.net, single(X_new));
        pred = double(raw(:));
    case 'cnn1d'
        pred = predict_cnn1d_seq(model, X_new);
    case 'direct_ridge'
        pred = [ones(size(X_new,1),1), X_new] * model.coef;
    otherwise
        error('core:predict_base_model','Unknown model type: %s', model.type);
end
end

function pred = predict_pnn(model, X_new)
sg = model.spread; pred = zeros(size(X_new,1),1);
for i = 1:size(X_new,1)
    d2 = sum((model.X_tr - X_new(i,:)).^2, 2);
    w  = exp(-d2/(2*sg^2)); sw = sum(w);
    if sw < 1e-300; pred(i)=mean(model.y_tr); else; pred(i)=(w'*model.y_tr)/sw; end
end
end

function pred = predict_cnn1d_seq(model, X_new)
if isempty(model.net); pred=nan(size(X_new,1),1); return; end
W=model.window; n=size(X_new,1); nf=size(X_new,2); ns=n-W+1;
if ns<=0; pred=nan(n,1); return; end
Xw=zeros(W,1,nf,ns,'single');
for j=1:ns; Xw(:,1,:,j)=reshape(single(X_new(j:j+W-1,:)),W,1,nf); end
pw=squeeze(double(predict(model.net,Xw))); pw=pw(:);
pred=nan(n,1); half=floor(W/2);
for i=1:numel(pw); idx=i+half; if idx<=n; pred(idx)=pw(i); end; end
pred=fillmissing(pred,'nearest');
end
