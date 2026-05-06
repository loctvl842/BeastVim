---
description: "Use when implementing code, writing new features, making changes, or generating a dev spec. Prevents common shortcuts and lazy excuses agents use to skip important steps."
---

# Anti-Rationalizations

Before skipping any step, check this table. If your reasoning matches an excuse below, follow the rebuttal instead.

| Excuse | Rebuttal |
|---|---|
| "It's a small change, skip the dev spec" | Small changes that touch APIs, auth, or data flow are architecturally significant. Write the spec. |
| "I'll add tests later" | Later never comes. Write the test now, even if it's minimal. |
| "I'll hardcode the URL/config/value" | Check existing patterns first. The project likely uses env vars or config files. Use them. |
| "The codemap doesn't need updating" | If you added a new route, service, or dependency, the codemap is stale. Update it. |
| "I'll copy from another file" | Copy the pattern, not the assumptions. Verify the approach still applies. |
| "I don't need to check existing code" | Search the repo before writing anything. The solution may already exist. |
| "This doesn't need error handling" | It does. Handle the failure case, even if it seems unlikely. |
| "I'll clean this up in a follow-up" | Clean it now. Follow-ups get deprioritized and forgotten. |
| "The existing code doesn't have tests so I won't add them" | Break the cycle. Add tests for your change even if surrounding code lacks them. |
| "I know the answer without looking it up" | Verify against docs or source. Training data may be outdated. |