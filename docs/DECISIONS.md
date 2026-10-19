# Sawti implementation decisions

Decisions are dated. A “proposed” decision is not runtime proof.

| ID | Date | Decision | Reason / status |
|---|---|---|---|
| D-001 | 2026-10-18 | Start from upstream commit `a4f6af6df2674bc4e18097084a128af469823fab` on local branch `sawti/dev` | This is the reviewed main commit; upstream `main` still resolved to this SHA at setup. No upstream patch head is assumed merged. |
| D-002 | 2026-10-18 | Keep Sawti fully separate from AcademiaOS through 1.0 | User-approved product scope. No AcademiaOS files, schema, process, import path or release dependency is included in Sawti work. |
| D-003 | 2026-10-18 | No production code or broad refactor before the helper feasibility gate | User-approved v1.1 execution order. First establish app/helper identity, permissions, actual audio handoff and kill/teardown behavior. |
| D-004 | 2026-10-18 | Candidate Sawti identity is `com.nourchkair.sawti`; the P0.4 development probe uses an isolated development suffix | Validate registration and live TCC attribution. It is a proposed identifier, not a registered Apple identity. Revalidate after every identity/signature change. |
| D-005 | 2026-10-18 | Keep origin fetch-only for routine use | Local `.git/config` sets `remote.origin.pushurl` to `disabled://sawti-upstream-read-only` and `push.default=nothing`. This does not create or authorize a Sawti hosting remote. |
| D-006 | 2026-10-18 | Keep model, feature and dependency pins unchanged during the feasibility probe | Avoid combining architecture evidence with model/download/dependency changes. Any version update needs its own measured regression case. |
| D-007 | 2026-10-18 | Do not install system developer tools or create/install a signing identity silently | Current host has Swift 6.0.3 and zero valid signing identities. A Swift 6.2-capable toolchain and stable local signing configuration are prerequisites to a meaningful GA capture test. |
| D-008 | 2026-10-18 | Host-model verification is provisional for the product requirement | The connected machine identifies as MacBook Air M2/8 GB. User's plan names a MacBook Pro M2/8 GB; exact Pro validation must be performed on that machine or the supported-hardware scope must be clarified before a release claim. |
