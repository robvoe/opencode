---
name: personal-notes
description: Organize, read, write, and reorganize a personal knowledge collection of notes, meetings, projects, tasks, activities, links, and referenced files. Use when capturing information, looking up open work or history, following up links, finding missing connections, or keeping the personal notes repository coherent.
---

# Personal Notes

Use this skill as the user's single point of truth for personal knowledge,
work history, tasks, projects, meetings, links, and related files. Activate it
for explicit note operations and when a current workflow exposes a missing
connection or information gap that can be resolved from the collection or from
links the user supplied.

## Locate The Collection

1. Read `<skilldir>/personal-notes-path.txt` as a single filesystem path.
2. Trim surrounding whitespace, reject an empty or invalid path, and stop with
   a clear error if the directory is unavailable.
3. Inspect the collection before changing it. Read its conventions, indexes,
   relevant notes, referenced files, and Git state when applicable.
4. Create `CONVENTIONS.md` lazily when it is absent. Document the current
   structure, naming and metadata conventions, task and activity model,
   reorganization policy, external-link policy, relationship decisions, and Git
   workflow. Never overwrite existing conventions.

Do not encode the collection path anywhere else in this skill. The path file is
machine-specific and may be changed when using the skill on another machine.

## Collection Model

Prefer a shallow, flexible layout. Create directories and files lazily:

```text
personal-notes/
├── README.md
├── index.md
├── CONVENTIONS.md
├── inbox/
├── meetings/
├── projects/
├── topics/
├── tasks/
│   ├── active.md
│   └── archive/
├── activity/
└── assets/
```

Do not force every entry into a rigid type or schema. Use descriptive names,
headings, and optional metadata such as dates, status, people, project aliases,
links, and source files. Markdown is the primary format. Scripts, images,
exports, and other files may accompany notes, but every such file must be
referenced from a Markdown note with a relative link.

Dates are required by default because they make freshness and history visible.
Add `Created` and `Updated` dates to notes, event dates to meetings and
activities, and `Due` or `Reminder` dates to tasks when applicable. Preserve
source dates when importing or promoting information. Never invent a date; omit
it or mark it unknown when no meaningful date is available. Undated evergreen
notes are an explicit exception, not the default.

Meeting notes are first-class capture documents. Preserve the original capture
and any supplied text or other source file. Extract durable facts, decisions,
tasks, relationships, and useful links into linked notes when that improves
retrieval; do not silently discard the source.

Projects, topics, meetings, activities, and captures are content forms rather
than mutually exclusive taxonomic types. Keep nesting shallow and link notes
with relative Markdown links. Maintain `index.md` as a useful navigation entry
point, updating it when notes are added, renamed, split, merged, or promoted.

## Write And Promote

When the user gives raw information, links, meeting notes, or files:

1. Capture the information without inventing facts or losing provenance.
2. Identify actionable tasks, durable knowledge, decisions, activities,
   people, projects, topics, and likely relationships.
3. Put the capture in the most appropriate shallow location, creating a new
   note when no existing note fits.
4. Promote stable facts, decisions, and tasks into the relevant topic or
   project notes and link them back to the source capture.
5. Repair or add links between related notes and referenced files.
6. Preserve uncertainty explicitly rather than presenting an inference as a
   fact.

When a user supplies a link, identify what it is about and what useful
information it may contain. When the purpose requires following it, create or
update a topic-relevant link dossier with the source URL, title, access or
updated date when known, a concise summary, relevant sections or facts, and
links discovered on the page with a hint about what each linked page contains.
Extract enough attributed information to remain useful if the source later
becomes unavailable, without mirroring or bulk-importing the page. Mark links
as inaccessible, stale, or needing verification when appropriate and preserve
the last verified information.

Tasks use optional dates and this shape when metadata is useful:

```markdown
- [ ] Task description
  - Status: todo
  - Created: 2026-08-20
  - Due: 2026-09-01
  - Source: [[meeting note]]
  - Related: [[project note]]
  - Context: [script](../assets/project/script.sh), https://example.com
```

Use `todo`, `doing`, `waiting`, `done`, and `cancelled` as the normal states.
Tasks may contain substantial context, scripts, web links, internal
documentation links, collaborators, outcomes, and supporting files. Keep
completed and cancelled tasks in dated archive files under `tasks/archive/`
while retaining their source and related-note links.

Activities include meetings, hackathons, work sessions, decisions,
accomplishments, and planned events whether or not they create tasks. Record
dates, participants, outcomes, related tasks, and reminders when relevant.
Use activities to preserve work history that cannot be reduced to a task.

## Read And Report

Answer requests by querying the collection rather than merely listing files.
Support at least these views:

- Open, overdue, waiting, or upcoming tasks
- Tasks grouped by topic, project, or state
- Research and learning backlog, including Kubernetes and GitOps topics
- Recent activity or a date-range work summary
- Work completed with a person or group
- Meeting decisions, unresolved questions, and linked follow-up tasks
- Related notes, duplicate information, and missing links

Use progressive retrieval to protect the context window. First load only the
smallest relevant index, convention, topic, task, or activity files. Follow
links to additional notes only as needed. Search archived or unrelated files
only when the relevant current material is insufficient or the user asks for
history. Summarize intermediate findings rather than loading an entire archive
into context.

Reminders are derived from explicit reminder or due dates. Surface them when
asked, during relevant writes, or when a requested review makes them useful.
Do not claim to send proactive notifications without a separate scheduler or
calendar integration.

## Reorganize On Proposal

After every write and when explicitly asked, inspect for stale or conflicting
structure, duplicate notes, misplaced information, missing links, project
aliases, topic shifts, and opportunities to split, merge, or move information.
Preserve source captures and meaningful history.

Never start or apply reorganization automatically, even when the change seems
obvious. Detection during another operation may produce a concise proposal,
but the skill must ask whether to start it now or postpone it. Record deferred
proposals in a suitable task, activity, or conventions section so they can be
started later without repeating the analysis.

Explicit requests such as “reorganize my notes” or approval to start a detected
proposal begin the reorganization process. Before changing layout, splitting,
merging, promotion, naming, relationships, or policy, invoke `/grilling` and
conduct its interview one question at a time. Include a recommended answer,
challenge assumptions, and continue until the user and the skill share an
understanding of the proposed structure. Do not make changes until the user
has approved the settled result.

Record confirmed relationships and rejected hypotheses in `CONVENTIONS.md` so
the same question is not asked again. If recurring friction suggests a better
structure or policy, use `/grilling` to examine the proposal, then request
approval before updating conventions.

Archive dated work records once they are more than one year old: meeting
notes, completed or cancelled tasks, activity records, and historical project
logs. Keep evergreen topic knowledge, active tasks, current project references,
decisions, and link dossiers readily available. Preserve links and provenance
when moving records into archive locations. Archived material remains
searchable, but is loaded only when relevant or explicitly requested.

External links are purpose-driven inputs, not an invitation to crawl. Fetch a
link only when needed to answer the user's request, extract relevant material,
or understand/reorganize a note. Extract only facts, decisions, procedures,
and links that are relevant; retain the source URL and attribution. Before
copying external information into the collection, propose the specific
integration. Never bulk-import or mirror external pages. Follow supplied
Confluence or other internal links under the same rule and only when access is
available.

## Git Synchronization

Detect Git with repository status commands. Never initialize Git automatically.
In a plain directory, skip synchronization without treating it as an error.

When meaningful changes accumulate or the user asks, offer synchronization.
Inspect status and actual staged and unstaged diffs, including relevant changes
made outside the current interaction. Select only files relevant to the
approved notes change; never silently use a blind `git add -A`. Show candidates
and allow individual inclusion or exclusion. Do not stage unrelated work.

Default to one combined commit. Offer separate commits when changes form
logically distinct groups. Use the project's conventional commit rules:
`feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `build`, or `chore`;
write an imperative, lower-case subject without a trailing period; use a scope
only when it adds context; include a body for motivation when useful.

At every staging/commit/push offer, use this exact report:

```text
To commit:

  staged (<n> files):
    added:     <new file>, <new file>
    modified:  <tracked file>
               <tracked file>

  left out (<n>):
    - <file> (reason)

  message: <proposed shorthand subject>
  steps:   git add <the staged files> → commit → push

OK to proceed?
```

Require explicit approval of the exact staging set, then separate explicit
approval before committing and before pushing. Show added, modified, deleted,
and renamed files, the proposed shorthand message, and a concise change
summary. Never amend, rewrite history, force-push, or include unrelated changes
unless explicitly requested.

## Guardrails

- Do not overwrite existing notes, conventions, or source captures without a
  clear reason and user approval where the change is uncertain.
- Do not invent dates, relationships, collaborators, project identities, or
  facts from an inaccessible source.
- Do not repeatedly ask a relationship question already recorded as accepted or
  rejected.
- Do not fetch links speculatively or bulk-copy external content.
- Keep all references to this skill's own files relative using `<skilldir>/`.
