# doc-audit-loop dashboard

```bash
cd scripts/doc-audit-loop/dashboard && npm install && npm run dev
```

Open `http://localhost:4322`.

This dashboard reads run artifacts from `../runs/latest/` (following the symlink target automatically).

The page has a top status header, a live iteration summary table in the main panel (click a row to inspect it), a right-side tabbed details panel for raw markdown outputs (`audit.md`, `validated.md`, `fix-report.md`, `review.md`), and a bottom live tail of `orchestrator.log` with a pause toggle.
