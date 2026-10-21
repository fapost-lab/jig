# Next task advice — which task to take next

Depth: easy — a placeholder that keeps a question the `contract-queue` epic left as fog; it is
stress-tested when the queue has been used.

## Idea

Moved from `contract-queue` when its epic was finished (maintainer, 2026-10-20): next-task
selection by priority, order and dependencies — how an agent or a person is advised what to take
— was not stated, and `contract-queue` deliberately left it out "until the queue has been used".

## Goal and problem

- Who is worse off without this, and how: since 0.31.0 the queue holds priority, order and
  dependencies, but nothing reads them to say what to take next; an agent or a person picks by
  hand, and a task waiting for another can be started first.
- What is true when the work is done: not stated yet.

## Stress test

- Not done yet: the question cannot be stated precisely before the queue has been used.

## Scope and non-goals

- In scope: advice on the next task from the queue (priority, order, dependencies, pause).
- Not doing: anything with a server or a UI — that is Jig UI's.

## Decisions

- None yet.

## Open questions

- Who asks — an agent at the start of a session, `jig status`, Jig UI — and in what form.
- Whether priority or position decides first, and what a dependency on an unfinished task does.

## Assumptions left untested

- That the queue as shipped in 0.31.0 is enough input — to check once it has been used.
