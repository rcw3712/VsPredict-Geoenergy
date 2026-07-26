# MODEL_SELECTION_REPORT.md
Run: run_20260723_170341

## Level 1 — Meta-learner selection
Criterion: highest Well-A internal holdout R²
Selected: ridge_stacker (holdout R²=0.2668)

## Level 2 — Overall deployable model
Criterion: minimum mean blocked-CV RMSE (k=5, common basis)
Best: ridge_stacker (CV RMSE=0.0482)

## Selection policy
Deployment model = Ridge stacker (Level-1 winner, meta-learner context).
Level-2 note: Ridge stacker (RMSE=0.0482) outperforms PNN (RMSE=0.0488) on CV
Well-B was NOT used for any model selection decision.
