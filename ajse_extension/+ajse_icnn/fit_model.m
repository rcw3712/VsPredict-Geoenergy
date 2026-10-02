function model = fit_model(X, y, hp, seed, segment_ids, model_label)
% AJSE_ICNN.FIT_MODEL  Segment-aware multi-scale I-CNN meta learner.
%   The caller must supply physical-depth segment IDs. Windows are built
%   only within a segment; crossing a gap is a hard error.

assert(nargin >= 6 && ~isempty(segment_ids), ...
    'ajse_icnn:MissingSegments', 'segment_ids is mandatory');
X = double(X); y = double(y(:)); segment_ids = double(segment_ids(:));
n = size(X,1); n_features = size(X,2);
assert(n == numel(y) && n == numel(segment_ids), ...
    'ajse_icnn:SizeMismatch', 'X, y, and segment_ids must have equal rows');
assert(all(isfinite(X),'all') && all(isfinite(y)) && all(isfinite(segment_ids)), ...
    'ajse_icnn:NonFinite', 'Training inputs must be finite');

W = hp.window;
segments = unique(segment_ids(:),'stable');
starts = zeros(0,1); anchors = zeros(0,1); segment_for_window = zeros(0,1);
for si = 1:numel(segments)
    ix = find(segment_ids == segments(si));
    assert(all(diff(ix)==1), 'ajse_icnn:NonContiguousSegment', ...
        'Each physical segment must occupy contiguous rows');
    nwin = numel(ix) - W + 1;
    assert(nwin > 0, 'ajse_icnn:ShortSegment', ...
        'Segment %g has %d rows, shorter than window %d', ...
        segments(si), numel(ix), W);
    starts = [starts; ix(1:nwin)]; %#ok<AGROW>
    anchors = [anchors; ix((1:nwin)+floor(W/2))]; %#ok<AGROW>
    segment_for_window = [segment_for_window; ...
        repmat(segments(si),nwin,1)]; %#ok<AGROW>
end

n_valid = numel(starts);
n_global_candidate = max(0,n-W+1);
n_discarded = n_global_candidate - n_valid;
assert(n_valid > 0 && n_discarded >= 0, ...
    'ajse_icnn:WindowAudit', 'Invalid window accounting');

Xw = zeros(W,1,n_features,n_valid,'single');
for wi = 1:n_valid
    rows = starts(wi):(starts(wi)+W-1);
    assert(all(segment_ids(rows)==segment_for_window(wi)), ...
        'ajse_icnn:CrossSegmentWindow', 'Cross-segment window retained');
    Xw(:,1,:,wi) = reshape(single(X(rows,:)),W,1,n_features);
end

y_mu = mean(y,'omitnan');
y_sigma = std(y,'omitnan');
if y_sigma < 1e-8; y_sigma = 1; end
y_scaled = (y-y_mu)/y_sigma;
y_tensor = reshape(single(y_scaled(anchors)),[1 1 1 n_valid]);
assert(max(abs(double(y_tensor(:))*y_sigma+y_mu-y(anchors))) < 1e-5, ...
    'ajse_icnn:TargetRoundTrip', 'Target scaling round-trip failed');

lg = layerGraph();
lg = addLayers(lg,imageInputLayer([W 1 n_features], ...
    'Name','input','Normalization','none'));
branch_names = strings(numel(hp.kernels),1);
for ki = 1:numel(hp.kernels)
    k = hp.kernels(ki);
    prefix = sprintf('k%d',k);
    branch = [ ...
        convolution2dLayer([k 1],hp.filters,'Padding','same', ...
            'Name',[prefix '_conv']), ...
        batchNormalizationLayer('Name',[prefix '_bn']), ...
        reluLayer('Name',[prefix '_relu'])];
    lg = addLayers(lg,branch);
    lg = connectLayers(lg,'input',[prefix '_conv']);
    branch_names(ki) = string([prefix '_relu']);
end
lg = addLayers(lg,depthConcatenationLayer(numel(hp.kernels),'Name','concat'));
for ki = 1:numel(branch_names)
    lg = connectLayers(lg,char(branch_names(ki)),sprintf('concat/in%d',ki));
end
head = [globalAveragePooling2dLayer('Name','gap'), ...
    fullyConnectedLayer(1,'Name','fc'),regressionLayer('Name','output')];
lg = addLayers(lg,head);
lg = connectLayers(lg,'concat','gap');

opts = trainingOptions('adam', ...
    'MaxEpochs',hp.epochs, ...
    'MiniBatchSize',hp.batch, ...
    'InitialLearnRate',hp.lr, ...
    'Shuffle','never', ...
    'Verbose',false, ...
    'ExecutionEnvironment','cpu', ...
    'GradientThreshold',1.0, ...
    'L2Regularization',1e-4);
rng(seed,'twister');
t0 = tic;
net = trainNetwork(Xw,y_tensor,lg,opts);
elapsed_seconds = toc(t0);

model = struct();
model.type = char(model_label);
model.status = 'HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION';
model.net = net;
model.hp = hp;
model.seed = seed;
model.y_mu = y_mu;
model.y_sigma = y_sigma;
model.n_train_rows = n;
model.n_input_features = n_features;
model.n_segments = numel(segments);
model.n_global_candidate_windows = n_global_candidate;
model.n_valid_windows = n_valid;
model.n_discarded_cross_segment = n_discarded;
model.n_retained_cross_segment = 0;
model.segment_policy = 'PHYSICAL_DEPTH_SEGMENTS_FAIL_CLOSED';
model.elapsed_seconds = elapsed_seconds;
assert(model.n_retained_cross_segment==0, ...
    'ajse_icnn:CrossSegmentWindow', 'Cross-segment window retained');
end
