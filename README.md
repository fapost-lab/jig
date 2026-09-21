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

By default a finished task waits in your working tree for you to review and commit. One personal
setting, `agent.git: pr`, lets the agent commit, push and open the pull request instead — it never
merges. Either way, `jig status` tells you where your review queue is.

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
> my AGENTS.md"*, or [add it by hand](https://jig.fapost.in/install#2-set-up-a-project).

## Roadmap

Nothing is planned right now.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how Jig is developed, tested and released.

## License

[MIT](LICENSE)
