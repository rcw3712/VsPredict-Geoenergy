function model = fit_pnn(X_train, y_train, hyperparams, seed, cfg)
% MODELS.FIT_PNN  Nadaraya-Watson kernel regression.
%   Returns a MODEL STRUCT (not predictions). Rule 10.4.
%   model.type  = 'pnn'
%   model.X_tr  = training data (needed for prediction)
%   model.y_tr  = training targets
%   model.spread = kernel bandwidth

rng(seed, 'twister');
model.type   = 'pnn';
model.spread = hyperparams.spread;
model.X_tr   = X_train;
model.y_tr   = y_train;
model.seed   = seed;
model.n_train= size(X_train,1);
model.n_feat = size(X_train,2);
fprintf('    [PNN] Fitted: n=%d, spread=%.4f\n', model.n_train, model.spread);
end
