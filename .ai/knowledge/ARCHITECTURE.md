# Architecture

Layers, top to bottom (dependencies point downward only):

1. **Runtime** (Claude Code, Codex) — reads `AGENTS.md`, invokes skills.
2. **Skills** — `skills/sdlc-*`; semantic procedures executed by the agent.
   Installed per runtime by an adapter; vendor-neutral content.
3. **Scripts** — `scripts/` → installed as `.ai/scripts/sdlc <command>`;
   deterministic, no LLM. Housekeeping additionally runs from a scheduler/hook.
4. **Project state** — `.ai/knowledge` (durable, tracked), `.ai/workspace` and
   `.ai/runtime` (transient, ignored).

Cross-cutting:

- **Adapters** (`adapters/<runtime>/`) touch only layers 1↔2: copy, transform, hooks.
- **Profiles** (`profiles/<stack>/`) plug into scripts (`verify`) and knowledge (rules).

Invariant: no layer calls upward. Skills call scripts; scripts never call skills or the
runtime. See `docs/SPEC.md` §4.
