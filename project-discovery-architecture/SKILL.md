---
name: project-discovery-architecture
description: >-
  Guide a new project from rough idea to well-understood product vision,
  architecture choices, and a staged implementation plan before coding. Use
  when the user is starting a new app, website, game, tool, SaaS product, or
  software project and wants help clarifying what to build. The skill requires
  asking focused questions one topic at a time, avoiding assumptions, producing
  an AI-readable project vision, walking through key technical decisions, and
  only then proposing small reviewable build stages. Also triggers on Korean
  requests such as "새 프로젝트 기획", "프로젝트 아키텍처 정해줘", "만들고 싶은 걸
  설명할게", "개발 계획 세워줘", "기술 스택 같이 정하자".
---

# Project Discovery Architecture

Use this skill to turn a user's early project idea into a clear product vision,
explicit architecture decisions, and a small-stage build plan. The goal is not
to rush into implementation. The goal is to make the project understandable
enough that a fresh AI session, engineer, designer, or stakeholder could pick it
up without the user re-explaining the basics.

## Core stance

Do not propose a plan immediately. First, discover what the user is trying to
build.

- Ask questions before making architecture or implementation recommendations.
- Ask about one topic at a time so the user can answer cleanly.
- Keep going until the product, users, workflows, constraints, and desired end
  state are clear.
- Do not fill gaps with assumptions, even small ones. If something matters, ask.
- When a detail is unknown but not important yet, label it as "deferred" rather
  than pretending it is decided.

## When to use

Use this skill when:

- The user says they are starting a new project.
- The user describes an app, site, game, tool, automation, SaaS product, or
  software idea and asks what to build next.
- The user wants help with project architecture, technical choices, or a build
  plan before implementation.
- The request is broad enough that coding immediately would require guessing
  product behavior, audience, data model, deployment target, or success criteria.

Do not use this skill for a narrow implementation task inside an already-defined
project unless the user explicitly asks to revisit the product or architecture.

## Discovery flow

Move through these topics in order. Ask one topic at a time. If the user's answer
reveals a new ambiguity inside the same topic, follow up before moving on.

1. **Product outcome**
   - What is being built?
   - What problem does it solve?
   - What should the finished product feel like to use?
   - What is out of scope for the first version?

2. **Users and context**
   - Who will use it?
   - What are they trying to accomplish?
   - Is this for personal use, a team, customers, public users, or internal
     operations?
   - What level of polish, reliability, and support is expected?

3. **Core workflows**
   - What are the main things users must be able to do?
   - What is the most important end-to-end flow?
   - What inputs does the system receive?
   - What outputs, screens, files, messages, or reports should it produce?

4. **Data and state**
   - What data must be stored?
   - What data is temporary versus long-lived?
   - What needs search, history, auditability, permissions, or backups?
   - Are there existing files, databases, APIs, or systems to integrate with?

5. **Interface and experience**
   - Does it need a web UI, mobile UI, desktop app, CLI, automation, API, or
     multiple surfaces?
   - What should the first screen or main workspace be?
   - What existing products or interaction patterns are useful references?

6. **Constraints**
   - Budget, timeline, team size, maintenance expectations.
   - Hosting, privacy, compliance, offline support, performance, localization.
   - Required languages, frameworks, platforms, accounts, or deployment targets.

7. **Success criteria**
   - How will the user know version 1 is successful?
   - What must be demoable?
   - What would make the project fail or feel wrong?

## Required artifact: project vision

After discovery is complete, write a structured project vision before discussing
technical decisions. It must be detailed enough for a fresh session to understand
the project without further context.

Use this shape:

```markdown
# Project Vision

## One-sentence summary

## Target users

## Problem and desired outcome

## Core workflows

## User experience expectations

## Data and integrations

## Constraints and non-goals

## Version 1 success criteria

## Open questions or deferred decisions
```

Clearly separate confirmed facts from open questions. If the user corrects the
vision, update it before moving on.

## Technical decision walkthrough

Only after the project vision is accepted, walk through major technical decisions
one at a time. Explain choices in plain language and flag anything expensive or
hard to undo.

Common decision areas:

- Frontend surface and framework.
- Backend shape: no backend, serverless functions, API server, job worker, local
  app, or hybrid.
- Database and storage model.
- Authentication and permissions.
- Hosting and deployment.
- Integrations and external APIs.
- File handling, media, background jobs, or realtime behavior.
- Testing, observability, analytics, and admin/debug tooling.

For each decision, present:

- The recommended default.
- One or two realistic alternatives.
- Why the recommendation fits the confirmed project vision.
- What would be costly to change later.
- What can safely be deferred.

Do not overwhelm the user with every decision at once. Get agreement on the
overall structure before producing the build plan.

## Build plan rules

After the product vision and architecture are agreed, propose a build plan broken
into small, reviewable stages. Do not present a giant monolithic plan.

Each stage should include:

- The user-visible outcome.
- The smallest useful scope.
- Files, modules, or systems likely to be touched if known.
- Acceptance criteria.
- Verification method.
- What remains intentionally out of scope.

Prefer stages that produce a working slice of the product over stages grouped
only by technical layer.

## Tool, connector, and skill guidance

Throughout discovery, tell the user when a specific tool, connector, or skill
would help the project. Be concrete about why.

Examples:

- GitHub for issues, PRs, CI, or repository work.
- Google Drive, Docs, Sheets, or Slides for source material or collaborative
  planning.
- Slack or Gmail for workflow integrations.
- Figma or Canva for design-heavy products.
- OpenAI Platform setup for AI-backed apps.
- Browser, Playwright, or app automation for end-to-end verification.

Do not ask the user to connect tools speculatively. Recommend a tool only when it
supports a confirmed project need.

## Response behavior

- Be curious and precise.
- Ask concise questions.
- Keep only one active discovery topic in each message.
- Summarize what is confirmed before changing phases.
- Do not start coding or scaffolding until the user has accepted the vision,
  architecture direction, and first build stage.
- If the user asks to skip discovery, briefly explain the risk, then follow their
  requested level of speed while still labeling assumptions clearly.
