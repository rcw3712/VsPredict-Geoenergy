# AJSE I-CNN comparator aggregate outputs

This directory contains the non-sensitive aggregate subset of
`run_AJSE_ICNN_corrected_20261001_111157`.

- Provenance class: `HISTORICAL_ARCHITECTURE_POST_HOC_REEVALUATION`.
- Corrected reference run: `run_PED_corrected_20260910_071523`.
- Well-B was not used for fitting or hyperparameter selection.
- No cross-segment CNN windows were retained.

Included files document configuration, source hashes, nested fold and pooled
metrics, same-well holdout metrics, external-population metrics, paired block
bootstrap contrasts, the full private-run manifest, and the numerical summary.

`AJSE_ICNN_SOURCE_MANIFEST.csv` is the immutable source manifest captured by
the numerical run. `AJSE_PUBLIC_SOURCE_MANIFEST.csv` hashes the portable
repository copy, whose only runner change is discovery of the lowercase
`ajse_extension` directory with backward compatibility for the original local
folder name.

Excluded from the public repository are proprietary well logs, row-level OOF,
holdout and external predictions, training ledgers, checkpoints, numerical MAT
files, and fitted model binaries. `PUBLIC_SUBSET_MANIFEST_SHA256.csv` is the
authoritative manifest for the files actually distributed here. The copied
`AJSE_ICNN_OUTPUT_MANIFEST.csv` describes the complete private run and is
retained only to document the excluded-artifact boundary.
