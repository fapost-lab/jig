# System docs — documentation for people, not only context for agents

Depth: normal — a product direction with one irreversible choice (where the documents live and
what Jig commits to supporting); the rest can be decided one question at a time.

## Idea

> есть такая мысль. Сейчас джиг хорошо создает доки для дальнейшей разработки, которая
> использвется как контекст. Но очень хочется, чтобы джиг умел еще создавать документацию как для
> бизнеса, так и для разработчика, что он понимал какое поле за что отвечает, какие флоу
> запускаются в каком сулчае. Сейчас мы обленились. Даже ревью делает агент, а разработчик не знает
> как ведет себя система и на что реагирует.
>
> для этого есть мысль использовать еще одну надстройку по типу джиг юай. Но как по мне сложность,
> кроме как поддерживать и синкать, в том, что у каждой компании могут быть свои стандарты и
> сторадж для такой документации. Как вариант делать свой сторадж. Но тут опять раздвоение, писать с
> нуля сторадж слишком затратно, можно использовать внешний готовый продукт и адаптрировать его,
> например https://www.bookstackapp.com/.
>
> но я не знаю можно ли использовать опенсорс продукт в других опенсор продуктах.

## Goal and problem

- Who is worse off without this, and how: the developer, who no longer knows how the system
  behaves because an agent wrote and reviewed the change; the business side, who cannot find what a
  field means or which flow a given event starts.
- What is true when the work is done: a project holds documentation on two levels, both current
  with the code — a business level a non-developer can read, and a developer level that explains
  the code's fields, flows and triggers.

## Stress test

- Hidden assumptions — "this holds only if …":
  - Documents fix the "nobody knows how it behaves" problem only if someone reads them. An agent
    that writes docs nobody opens is the same laziness one step further.
  - Generated documentation is trusted only if it is kept current with the code; Jig already has the
    mechanism for that on knowledge (paths in frontmatter, `reviewed_at`, ADR-0010), not on docs for
    people.
- The main trade-off: one source of truth in the repository versus meeting each company in the
  storage it already uses.
- The weakest point: the full recovery pass at adoption produces more proposals than a person will
  read, so they are accepted unread and observed bugs become agreed requirements.
- Failure modes — cause, what breaks, the signal that shows it:
  - Batch acceptance of recovered criteria — bugs written down as requirements — a large accept
    with no criterion edited or rejected.
  - Knowledge and the documents for people drift apart — a person reads behaviour the code no longer
    has — a change to bound code whose consolidation updated only one of the two.
- Other shapes considered, and why this one: a stage in the route where a human confirms the
  behaviour change instead of any reference — kept in part, as acceptance criteria approved at
  analysis; Jig's own store or an external store as the source — rejected (Decisions).

## Scope and non-goals

- In scope: acceptance criteria as the business level, a developer level about fields, flows and
  triggers, both bound to code and kept by consolidation; a recovery pass at adoption; a publishing
  contract, with edits in a published copy coming back as tracker issues.
- Not doing: a document store of Jig's own; two-way sync; a renderer of Jig's own; what happens to
  an issue once filed (`issue-intake`).

## Decisions

- Two levels of documentation, both in scope. The business level is acceptance criteria: what the
  system does, for whom, in which case, in the reader's words. The developer level is about the
  code: what each field means, which flow an event starts, what the system reacts to. — rejected:
  choosing only one, because the user named both as the problem (the business cannot read code, the
  developer stopped reading it).
- Acceptance criteria have two sources. A task writes new ones at analysis, a human approves them,
  and consolidation carries them into the feature's living document. Code that existed before Jig,
  or before the criteria, gets them recovered by an agent from the code and its tests. — rejected:
  only the task, because most code a task touches predates it; only recovery, because criteria read
  off the code describe what it does, not what it should do, and a bug becomes a requirement.
- A recovered criterion is a proposal until a human confirms it — the same proposed → accepted
  lifecycle knowledge already has (ADR-0016, ADR-0018). It is marked as observed behaviour, so a
  reader never takes it for an agreed requirement.
- Recovery runs once over the whole project when Jig is adopted, the way `jig-map` maps knowledge;
  from then on tasks keep the criteria current. — rejected: recovering only the area a task is about
  to change, because coverage would never become complete and the business would get a reference
  with holes wherever nobody happened to work.
- Documentation for people is a separate set of documents from knowledge, written in plain
  conversational language; knowledge stays terse and written for agents. — rejected: one source
  rendered for both readers, because a document dry enough for an agent is hard for a person to read
  and take in, and readability is the point of this work.
- Because there are two copies, the documents for people carry the same `paths:` binding to code as
  knowledge, so the staleness check (ADR-0010) and consolidation reach them too: a task that changes
  bound code has to decide about both. Agents do not receive them through `jig context` — the
  knowledge already says the same thing to them.
- The repository is the one source of truth for the documents for people; everything else is a
  published copy. Two people changing one document meet in a git conflict, resolved like code in
  the pull request that also changes the code it describes. — rejected: Jig's own storage, because
  writing one is far beyond the value; an external store as the source with two-way sync, because two
  sources of truth conflict outside git, where nothing resolves them.
- Licensing does not decide the store: BookStack (MIT) may be used or integrated freely; it is one
  possible publishing target, never a requirement (ADR-0002).
- An edit made in a published copy's own UI comes back as a change request, never as truth: the
  adapter compares the page with what it last published and files the difference. The next publish
  overwrites the page with what the repository then holds. — rejected: one-way publishing only,
  because the business and QA would have no way to ask for a change where they read.
- A change request leaves this spec as an issue in the project's own tracker; what happens to it
  next — triage, a task, a pull request, escalation to a developer — is the spec `issue-intake`. —
  rejected: keeping intake here, because it serves QA bug reports and support requests just as well,
  without any documentation.

## Open questions

- How the full pass keeps a human reading — hundreds of recovered criteria invite accepting them in
  one batch, which is the same laziness at adoption. Decides how `jig-accept` presents them (per
  domain, per flow) and whether an unconfirmed criterion may stay proposed indefinitely.
- What Jig ships for publishing when it cannot know the client's renderer — a neutral contract
  (document tree, manifest, a `publish` and a `pull` command) with adapters as project code, the
  way project hooks run project code (`.ai/specs/project-hooks/`). Decides how many adapters Jig
  maintains itself, if any.

## Assumptions left untested

## Facts found

- BookStack is MIT-licensed, as is Jig. MIT permits use, modification and redistribution inside
  another open-source (or commercial) product, provided the copyright and licence notice are kept.
  Talking to it over its HTTP API does not make Jig a derivative work at all. Licensing is not the
  obstacle.
- BookStack is a PHP + MySQL server. Shipping or requiring it contradicts ADR-0002 (POSIX sh and git
  only) and the zero-config audience Jig targets; it can only ever be one optional target, never the
  store.
