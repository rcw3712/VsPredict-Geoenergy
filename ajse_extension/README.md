# AJSE I-CNN Comparator Extension

This extension re-evaluates the historical I-CNN and Hybrid I-CNN
meta-learners under the corrected, segment-aware pipeline without modifying
the frozen canonical run.

Scientific status: `HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION`.

Fixed architecture inherited from the predecessor project:

- multi-scale kernels `[3, 5, 7]`;
- 32 filters per branch;
- learning rate `1e-4`;
- 200 epochs;
- mini-batch 32;
- window length 16;
- CPU execution and `Shuffle='never'`.

No hyperparameter is selected using Well-B. Physical depth-segment IDs are
mandatory for training and prediction, and cross-segment windows are rejected.

Run from the repository root in MATLAB:

```matlab
addpath('ajse_extension')
selftest_ajse_icnn_comparator
result = run_ajse_icnn_comparator;
```

The committed aggregate output subset is under
`results/ajse_icnn_20261001`. Proprietary inputs, row-level predictions,
checkpoints, and fitted model binaries are intentionally excluded.
