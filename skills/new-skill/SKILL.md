---
name: new-skill
description: Create a new opencode skill from the history of the current session. Use when the user wants to capture what they just did into a reusable SKILL.md, e.g. "make a skill of what we just did", "skill-ify that", "create a skill from this session", "new skill". Walks through suggesting skill-worthy threads, confirming scope, iterative drafting, naming, and writing the file.
---

# new-skill

Turn the current session's history into a reusable opencode skill.

## When to use me

Use when the user wants a skill based on something they just did in this session. Trigger words/phrases: "create a skill", "make a skill", "new skill", "skill-ify", "turn this into a skill", "capture this as a skill".

## Workflow

**Fixed sequence: (1) suggest candidates only, (2) a go/no-go question, (3) then the grilling — and only on the candidates the user picked. Iteration within the grilling is the point: questions on questions, one at a time, each answer feeding the next. Location and name come at the very end. Do not write anything until the user has confirmed we share an understanding.**

1. **Suggest candidates — this step does nothing else.** Scan the session for the most skill-worthy threads and surface them as suggestions. Ask the user whether searching other sessions makes sense too. History normally comes from the current context; fall back to `opencode export <sessionID>` or `opencode db query` when the session was compacted or the user points at an older session. No grilling, no drafting yet.
2. **Go/no-go.** Right after presenting the candidates, ask the user whether they actually want to skill-ify at all, and which candidate(s) to proceed with. Provide your recommendation. Continue only after the user picks candidates. If they decline, report plainly and stop — never force a skill.
3. **Start grilling — only on the confirmed candidates.** Only now does the grilling begin, restricted to exactly the candidates the user chose. Run as a `/grilling` session: interview relentlessly, one question at a time, questions on questions — every answer feeds the next. Iterate through scope, content, structure, pitfalls, and anything underspecified until it is genuinely settled. Facts you can look up yourself (session history, existing skills, config paths) you must look up rather than asking about. For each question, provide your recommended answer. Do not move to drafting until the grilling has settled the skill.
4. **Draft.** Distill the grilled-and-settled essence + pitfalls into a docs-style SKILL.md: an overview line, procedural steps, and a pitfalls/warnings section. Strip one-off specifics (real file paths, session IDs, dates) and generalize concrete examples into templates. When the SKILL.md references the skill's own companion files, only ever use relative paths with the `<skilldir>/` prefix (e.g. `<skilldir>/colleague-absences.sh`), never absolute paths (`/Users/...`) or semi-absolute ones (`~/.config/opencode/skills/<name>/...`). If part of the procedure is better expressed as a companion file — a helper script, a format spec doc (like `domain-modeling`'s `CONTEXT-FORMAT.md`), or an `agents/openai.yaml` — propose adding it to the skill's folder as a question — never add a companion file without the user's explicit confirmation. Use this skill's companion file `NEW-SKILL-FORMAT.md` as well as its `SKILL.md` as the reference for the structure of generated skills, while explicitly leaving it open to insert/rename/rearrange sections if helpful.
5. **Environment (for scripted skills).** If a confirmed helper script depends on non-standard (third-party) modules, the generated skill should include the following instructions on how to run it: if an environment is already active (e.g. `VIRTUAL_ENV`, `CONDA_PREFIX`, or an active `pdm`/`uv` context), use it; otherwise ask the user which environment to run the script with, leaving the user the option to abort skill execution. This is a question, not an assumption.
6. **Name.** Derive the name from the settled content's core action. Validate against `^[a-z0-9]+(-[a-z0-9]+)*$` and check uniqueness across load locations. Present the candidate name(s) to the user as a question and get their confirmation before continuing.
7. **Description.** Write trigger-first and in third person (e.g. "Use when..."), with "Use ONLY when..." gating where apt. Frontmatter is minimal and always `name` + `description` — nothing else. Ask the user individually which location the new skill should go in — project `.opencode/skills/` or global `~/.config/opencode/skills/` — as a question with a recommendation, and wait for the answer.
8. **Write.** Create `<location>/<name>/SKILL.md` and any confirmed companion files in the same folder (files are referenced relatively from the skill's base directory), including -unless the user declines- `<skilldir>/agents/openai.yaml` with `interface.display_name`, `interface.short_description`, and — only when the skill gates model invocation — `policy.allow_implicit_invocation: false`. In every code sample that touches the skill's own files, use `<skilldir>/<file>` as the path — never `~/.config/opencode/skills/<name>/<file>` or any absolute path. Verify the file(s) landed, the folder name matches the skill name, and the front matter is correctly formatted: the file must start with a `---` block containing the `name` field (lowercase, hyphen-separated, equal to the folder name and matching the regex) and the `description` field — never missing, never malformed. Restrict the front matter to the recognized fields `name`, `description`, `license`, `compatibility`, `metadata` — never emit unknown fields (e.g. `disable-model-invocation`), they are silently ignored by opencode. Fix the front matter before finishing if it is wrong.
9. **Wrap up.** Ask the user whether anything else from the session is worth skill-ifying (one question, with your recommendation), and remind the user to restart opencode for the new skill to be discovered. If nothing reusable is found, report that plainly and stop rather than forcing a skill.

## Pitfalls

- Never run through the workflow without grilling — every decision (scope, name, description, location, environment, further candidates) must be asked, one question at a time, with a recommended answer, and the answer awaited. Do not default, guess, or proceed on your own.
- Never write a file before the user has confirmed we share an understanding.
- Never start a file with a missing or malformed front matter block: the `---`-delimited front matter with `name` + `description` is mandatory, correctly formatted, at the very top of the file.
- Never emit front matter fields other than `name`, `description`, `license`, `compatibility`, `metadata` — unknown fields (e.g. `disable-model-invocation`) are silently ignored by opencode.
- Never let `agents/openai.yaml` fall out of sync with the SKILL.md: if `policy.allow_implicit_invocation` is declared there, it must match any mention of implicit invocation in the SKILL.md — including on later edits to the skill.
- Never mix up the ordering: candidates first, then a go/no-go, then grilling exclusively on the chosen candidates. Never grill before candidates are chosen, and never drift onto candidates the user did not pick.
- Never force a skill from one-off work — report and stop instead.
- Never guess the location; ask each time.
- Never add companion files without the user's confirmation.
- Never hardcode absolute (`/Users/...`) or semi-absolute (`~/.config/opencode/skills/<name>/...`) paths to the skill's own files in the SKILL.md — reference them with `<skilldir>/...` instead.
- The name must match both the regex `^[a-z0-9]+(-[a-z0-9]+)*$` and the folder name.
