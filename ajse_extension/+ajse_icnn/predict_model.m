function [pred, audit] = predict_model(model, X, segment_ids)
% AJSE_ICNN.PREDICT_MODEL  Segment-aware prediction for an I-CNN model.

assert(nargin>=3 && ~isempty(segment_ids), ...
    'ajse_icnn:MissingSegments', 'segment_ids is mandatory');
X = double(X); segment_ids = double(segment_ids(:));
n = size(X,1); W = model.hp.window; n_features = size(X,2);
assert(n==numel(segment_ids) && n_features==model.n_input_features, ...
    'ajse_icnn:SizeMismatch', 'Prediction input dimensions do not match model');
assert(all(isfinite(X),'all') && all(isfinite(segment_ids)), ...
    'ajse_icnn:NonFinite', 'Prediction inputs must be finite');

pred_scaled = nan(n,1); n_valid = 0;
segments = unique(segment_ids(:),'stable');
for si = 1:numel(segments)
    ix = find(segment_ids==segments(si));
    assert(all(diff(ix)==1), 'ajse_icnn:NonContiguousSegment', ...
        'Each physical segment must occupy contiguous rows');
    nwin = numel(ix)-W+1;
    assert(nwin>0, 'ajse_icnn:ShortSegment', ...
        'Segment %g has %d rows, shorter than window %d', ...
        segments(si),numel(ix),W);
    Xw = zeros(W,1,n_features,nwin,'single');
    for wi = 1:nwin
        rows = ix(wi:wi+W-1);
        assert(all(segment_ids(rows)==segments(si)), ...
            'ajse_icnn:CrossSegmentWindow', 'Cross-segment window retained');
        Xw(:,1,:,wi)=reshape(single(X(rows,:)),W,1,n_features);
    end
    pw = double(squeeze(predict(model.net,Xw))); pw = pw(:);
    anchors = ix((1:nwin)+floor(W/2));
    pred_scaled(anchors)=pw;
    seg_pred=pred_scaled(ix);
    seg_pred=fillmissing(seg_pred,'nearest');
    pred_scaled(ix)=seg_pred;
    n_valid=n_valid+nwin;
end
pred=pred_scaled*model.y_sigma+model.y_mu;
assert(all(isfinite(pred)), 'ajse_icnn:IncompletePrediction', ...
    'Prediction contains NaN or Inf');
n_global=max(0,n-W+1);
audit=table(n,numel(segments),W,n_global,n_valid,n_global-n_valid,0, ...
    'VariableNames',{'N_ROWS','N_SEGMENTS','WINDOW', ...
    'N_GLOBAL_CANDIDATE','N_VALID','N_DISCARDED_CROSS_SEGMENT', ...
    'N_RETAINED_CROSS_SEGMENT'});
end
