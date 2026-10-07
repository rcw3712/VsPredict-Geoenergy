# Journal of Applied Geophysics submission release

## Scope

This release supports the manuscript:

> **External-Well Transferability of Synthetic Shear-Wave Velocity under Severe Sonic-Log Shift: A Record-Disjoint Two-Well Case Study**

The evidence is limited to one calibration well and one record-disjoint external-well transfer event. The release does not claim field-wide geological generalization.

## Scientific hierarchy

- Frozen primary model: Ridge stacker from the corrected reference pipeline.
- Historical-architecture post-hoc comparators: I-CNN and Hybrid I-CNN.
- Post-hoc exploratory benchmark: Direct Ridge with nominal `lambda = 1.0` fixed in the extension configuration.
- Pop-A: primary exact-copy-excluded external population (`n = 329`).
- Pop-B: target-informed diagnostic subset (`n = 236`), not a deployable primary evaluation population.

## Neutral provenance aliases

| Alias | Immutable source identifier |
|---|---|
| `R1` | `run_PED_corrected_20260910_071523` |
| `E1` | `ped_extension_run_PED_corrected_20260910_071523_20260910_114659` |
| `C1` | `run_AJSE_ICNN_corrected_20261001_111157` |

Legacy journal strings occur only inside immutable identifiers and historically named code paths. They do not define the current journal target.

## Public/private boundary

The public release contains source code, aggregate metrics, figures, source summaries, and cryptographic manifests. It excludes proprietary well logs, row-level predictions, training ledgers, checkpoints, numerical MAT files, and fitted model artifacts.

## Integrity

The release manifest records SHA-256 hashes for the JAG figure package and the source-run manifest mapping. No predictive model was rerun or retuned to create the JAG release.
