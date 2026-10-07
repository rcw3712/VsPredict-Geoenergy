# Archive scope and version mapping

## GitHub

The repository `rcw3712/VsPredict-NRR` is retained as the umbrella project-history archive. Its name records an earlier journal-target phase and does not imply that every branch or release targets that journal.

The current JAG submission is identified by:

- corrected reference run `run_PED_corrected_20260910_071523`;
- corrected extension manifest `ped_extension_run_PED_corrected_20260910_071523_20260910_114659`;
- historically named comparator run `run_AJSE_ICNN_corrected_20261001_111157`;
- figure directory `figures/jag-submission-20261007`;
- aggregate result directories `results/ped_corrected_20260910` and `results/ajse_icnn_20261001`.

The legacy `PED` and `AJSE` strings above are immutable run identifiers, not the current journal target. Earlier tags and branches remain provenance snapshots. Their numerical values must not be substituted for the JAG values.

## Zenodo

The concept DOI is `10.5281/zenodo.21614275`. Existing NRR/PED-era versions remain historical snapshots. The JAG release is defined by tag `jag-2026.10-submission` and must receive its own version-specific Zenodo DOI.

## Integrity requirements for the JAG release

1. Tag the final JAG commit without rewriting earlier tags.
2. Attach source code, non-sensitive aggregate outputs, and the run-labelled figure package.
3. Verify the canonical, extension, comparator, and figure SHA-256 manifests.
4. State that row-level predictions, proprietary well logs, checkpoints, and model binaries are excluded.
5. Record the Git commit SHA and version-specific Zenodo DOI in the accepted-manuscript metadata.
