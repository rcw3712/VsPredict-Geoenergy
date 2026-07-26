function model = fit_base(X_train, y_train, model_name, hp, seed, cfg)
% MODELS.FIT_BASE  Dispatcher for all base learner fitting.
%   Returns a model STRUCT (Rule 10.4 — fit/predict separation).
%   cfg.training.shuffle = 'never' (Rule §4.2).
rng(seed, 'twister');
switch lower(model_name)
    case 'pnn';    model = fit_pnn_impl(X_train, y_train, hp, seed);
    case 'mlffnn'; model = fit_nn_impl(X_train, y_train, hp, seed, cfg, 'mlffnn');
    case 'dffnn';  model = fit_nn_impl(X_train, y_train, hp, seed, cfg, 'dffnn');
    case 'cnn1d';  model = fit_cnn1d_impl(X_train, y_train, hp, seed, cfg);
    otherwise;     error('models:fit_base','Unknown model: %s', model_name);
end
model.type        = model_name;
model.seed        = seed;
model.n_train     = size(X_train,1);
model.n_feat      = size(X_train,2);
end

function model = fit_pnn_impl(X, y, hp, seed)
if isfield(hp,'spread'); sp=hp.spread; else; sp=0.5; end
model.spread = sp;
model.X_tr   = X;
model.y_tr   = y;
end

function model = fit_nn_impl(X, y, hp, seed, cfg, arch)
% MLFFNN: 1 hidden layer. DFFNN: 2 hidden layers, sequential (no residual skip).
if isfield(hp,'hidden'); hidden=hp.hidden; else; hidden=[64,32]; end
if isfield(hp,'lr');     lr=hp.lr;         else; lr=1e-3;        end
if isfield(hp,'epochs'); ep=hp.epochs;     else; ep=200;         end
if isfield(hp,'batch');  bs=hp.batch;      else; bs=32;          end
n_in = size(X,2); n_out = 1;

layers = [featureInputLayer(n_in,'Normalization','none')];
for hi = 1:numel(hidden)
    layers = [layers, ...
        fullyConnectedLayer(hidden(hi)), ...
        batchNormalizationLayer, reluLayer]; %#ok<AGROW>
end
layers = [layers, fullyConnectedLayer(n_out), regressionLayer];

opts = trainingOptions('adam', ...
    'MaxEpochs',          ep, ...
    'MiniBatchSize',      bs, ...
    'InitialLearnRate',   lr, ...
    'Shuffle',            cfg.training.shuffle, ...
    'Verbose',            false, ...
    'ExecutionEnvironment','cpu');

rng(seed,'twister');
% R2024a: trainNetwork expects X as numObs×numFeatures, y as numObs×1
% Do NOT transpose X or y
model.net = trainNetwork(single(X), single(y(:)), layers, opts);
model.arch = arch;
end

function model = fit_cnn1d_impl(X, y, hp, seed, cfg)
if isfield(hp,'filters'); nf=hp.filters(1); else; nf=32; end
if isfield(hp,'lr');      lr=hp.lr;         else; lr=1e-3; end
if isfield(hp,'epochs');  ep=hp.epochs;     else; ep=200;  end
if isfield(hp,'batch');   bs=hp.batch;      else; bs=32;   end
W = cfg.base.window;
n_feat = size(X,2); n = size(X,1); n_seq = n - W + 1;
if n_seq <= 0; model.net=[]; model.window=W; return; end

% Reshape: [W 1 n_feat n_seq] — height=W, width=1, channels=n_feat
Xw = zeros(W, 1, n_feat, n_seq, 'single');
for j = 1:n_seq; Xw(:,1,:,j) = reshape(single(X(j:j+W-1,:)), W, 1, n_feat); end
half = floor(W/2);
% Align y to windowed output positions
y_seq_col = y(half+1:min(n, n_seq+half));
n_y = numel(y_seq_col);
if n_y ~= n_seq
    % Pad or trim to match exactly n_seq
    if n_y < n_seq; y_seq_col(end+1:n_seq) = mean(y_seq_col,'omitnan'); end
    y_seq_col = y_seq_col(1:n_seq);
end
% R2024a imageInputLayer: Y must be [numOutputs × 1 × 1 × numObs]
% Using 2D row (1×n_seq) causes R2024a to interpret as [1×1×n_seq] → mismatch.
% Explicit 4D reshape resolves this.
y_seq = reshape(single(y_seq_col(:)), [1, 1, 1, n_seq]);

% [height=W, width=1, channels=n_feat]: correct geometry for 1D temporal convolution
layers = [imageInputLayer([W 1 n_feat],'Normalization','none'), ...
    convolution2dLayer([3 1],nf,'Padding','same'), batchNormalizationLayer, reluLayer, ...
    convolution2dLayer([5 1],nf,'Padding','same'), batchNormalizationLayer, reluLayer, ...
    globalAveragePooling2dLayer, fullyConnectedLayer(1), regressionLayer];

opts = trainingOptions('adam','MaxEpochs',ep,'MiniBatchSize',bs,...
    'InitialLearnRate',lr,'Shuffle',cfg.training.shuffle,...
    'Verbose',false,'ExecutionEnvironment','cpu');

rng(seed,'twister');
model.net    = trainNetwork(Xw, y_seq, layers, opts);
model.window = W;
end
