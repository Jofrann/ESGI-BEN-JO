# Responsive verification — 2 November 2026

Scope: shared CampusRide widget layout. No database, authentication, or business-rule changes.

Local browser fixture uses synthetic data and rejects every backend request; no production rows are written.

- 320 CSS px: publish fields stack; no horizontal overflow; inputs 16px; phone minimum height 0px. Long stop value retained after missing-field validation. Leave-form dialog fits (278px), Escape closes it.
- 390 CSS px: results filters stack; cards fit; all five navigation targets are 67px tall. Selecting eight seats shows the empty state.
- 768 CSS px: publish form returns to two columns (349px each), without horizontal overflow.
- 640 × 320 CSS px landscape: keyboard reaches bottom navigation, outer document scrolls (898px), no nested form scroll region.
- JSX compiled using esbuild; strict frontend audit reports zero findings.

Published verification is recorded separately after Appsmith imports the commit. Viewport values are measured from the DOM because the user's Appsmith browser zoom affects the emulation dimensions.
