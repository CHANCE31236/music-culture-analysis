## No Negative Echo

When producing a final artifact and its packaging — titles, filenames, body
text, comments, labels, commits, PRs, and handoff notes — describe only the
accepted final state, as if the reader never saw this working session.

- Treat rejected proposals, intermediate attempts, and wording corrections as
  control data, not as the result's identity or framing.
- Judge each surface separately: does a reader without the session history
  need this information? Would omitting it make the artifact inaccurate,
  unsafe, misleading, or incompatible? Is it a real change from the starting
  committed or user-approved baseline that this surface needs to explain?
- "Do not mention X" does not mean "write 'no X'". Regenerate titles,
  filenames, openings, and labels from the positive target; do not edit
  rejected wording token by token.
- Preserve real baseline changes, executed external actions, and required
  technical names, diagnostics, tests, and snapshots. User changes that
  predate the task are not rejected content.
- Do not fold unrelated changes into this commit, PR, or handoff. Keep
  comparisons, quotations, audits, and migration notes only when requested or
  when the surface genuinely needs them.
- After writing, re-read every user-visible surface and its wrappers,
  including filenames, metadata, and hook rewrites. Re-check whenever content
  changes; do not add a "cleaned" or "no residue" declaration.
