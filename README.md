# Jig

Jig is a framework for building software with an AI coding agent — Claude Code or Codex. You
describe what you want in plain words; the agent sizes the work by its risk, keeps the project's
knowledge up to date, and stops to ask you where a human decision matters.

Jig lives inside your project: a folder of project knowledge committed with the code, skills your
agent follows, and a small shell tool the agent runs for the mechanical parts. Nothing is hosted,
there is no telemetry, and no script ever calls an AI model.

**Documentation: [jig.fapost.in](https://jig.fapost.in)**

## Who it is for

Anyone who builds software through an agent and wants it done carefully — a typo fixed in three
steps, a change to authentication designed, approved by you and independently reviewed. It works
for a [new project](https://jig.fapost.in/greenfield), started from an idea, and for an
[existing one](https://jig.fapost.in/brownfield), whose documentation it adopts instead of copying.

## Install

Jig runs on macOS, Linux and Windows. It needs Git and a coding agent; nothing else.

macOS and Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/fapost-lab/jig/main/install.sh | bash
```

Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/fapost-lab/jig/main/install.ps1 | iex
```

Then, in your project, run `jig init`, commit, and tell your agent *"set up Jig for this project"*.
[Install](https://jig.fapost.in/install) explains what each step does and how to update.

> **Already have your own `AGENTS.md` or `CLAUDE.md`?** `jig init` never changes them, so your agent
> will not know Jig's workflow until they carry the Jig section. Ask your agent to *"connect Jig to
> my AGENTS.md"*, or [add it by hand](https://jig.fapost.in/install#2-set-up-a-project) — keeping the
> `<!-- jig:begin -->` / `<!-- jig:end -->` lines, so `jig upgrade` keeps that section current.

## How much you hand over

By default a finished task waits in your working tree for you to review and commit. From there you
hand over in steps, and nothing you turn on reaches the rest of the team — the settings live in a
gitignored file of your own:

- **`agent.git`** — how far a finished task travels: committed, pushed, or an open pull request.
  Only the last level, `merge`, also merges, and only once your CI is green
  ([how](https://jig.fapost.in/agent-ships)).
- **Autopilot** — ask for it on a task and the agent runs its whole route without waiting between
  stages, has a second agent review the code, caps itself at two attempts to fix what the review or
  the checks found, and comes back with the change handed over and a report
  ([how](https://jig.fapost.in/autopilot)).
- **`autopilot.unattended`** — for when the questions a run would ask are not yours to answer: it
  takes the careful option instead and writes down in the pull request every choice it made in your
  place ([how](https://jig.fapost.in/autopilot#without-stops)).

A review records each problem it finds with a severity, and a serious one blocks the task from being
finished whichever of the above you chose. Wherever you stop, `jig status` — in the terminal, or as
a page you keep open in the browser — tells you what is waiting for you.

## Changelog

What each release changed: [jig.fapost.in/changelog](https://jig.fapost.in/changelog).

## Roadmap

Nothing is planned right now.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how Jig is developed, tested and released.

## License

[MIT](LICENSE)
