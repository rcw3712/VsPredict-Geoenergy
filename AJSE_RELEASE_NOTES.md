# AJSE submission release notes

## Scientific hierarchy

- Frozen primary model: Ridge stacker from the corrected reference pipeline.
- Historical-architecture post-hoc comparators: I-CNN and Hybrid I-CNN.
- Post-hoc exploratory benchmark: Direct Ridge.
- Pop-A is the primary exact-copy-excluded external population.
- Pop-B is a target-informed diagnostic subset and is not a deployable primary
  evaluation population.

## Authoritative identifiers

- Corrected reference: `run_PED_corrected_20260910_071523`.
- Corrected extension: `ped_extension_run_PED_corrected_20260910_071523_20260910_114659`.
- AJSE comparator: `run_AJSE_ICNN_corrected_20261001_111157`.

Legacy `PED` strings are immutable run identifiers retained for traceability;
they do not denote the current journal target.

## Corrections represented in this commit

- Canonical stacker meta-feature scaling and prediction path.
- Segment-aware CNN window construction.
- Five-value frozen PNN spread grid: `0.1, 0.2, 0.5, 1.0, 2.0`.
- Exact-copy rather than shared-depth exclusion terminology.
- Target-informed measured Vp/Vs screen terminology for Pop-B.
- AJSE-specific I-CNN and Hybrid I-CNN comparator evidence.

## Public/private boundary

This public repository omits proprietary well logs, row-level predictions,
training ledgers, checkpoints, numerical MAT files, and fitted model artifacts.
It contains source code, aggregate metrics, figures, and SHA-256 manifests.
