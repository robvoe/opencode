---
name: new-skill
description: Create a new opencode skill from the history of the current session. Use when the user wants to capture what they just did into a reusable SKILL.md, e.g. "make a skill of what we just did", "skill-ify that", "create a skill from this session", "new skill". Walks through suggesting skill-worthy threads, confirming scope, iterative drafting, naming, and writing the file.
---

# new-skill

Turn the current session's history into a reusable opencode skill.

## When to use me

Use when the user wants a skill based on something they just did in this session. Trigger words/phrases: "create a skill", "make a skill", "new skill", "skill-ify", "turn this into a skill", "capture this as a skill".

## Workflow

1. **Suggest candidates.** Scan the session for the most skill-worthy threads and surface them as suggestions. Ask the user whether searching other sessions makes sense too. History normally comes from the current context; fall back to `opencode export <sessionID>` or `opencode db query` when the session was compacted or the user points at an older session.
2. **Confirm scope.** Let the user pick which part of the session to encode.
3. **Draft.** Distill essence + pitfalls into a docs-style SKILL.md: an overview line, procedural steps, and a pitfalls/warnings section. Strip one-off specifics (real file paths, session IDs, dates) and generalize concrete examples into templates. Ask clarifying questions only if something is ambiguous. If part of the procedure is better expressed as a helper script (notably Python), propose adding it to the skill's folder — never add a script without the user's explicit confirmation. Use this skill (`new-skill`) as the reference for the structure of generated skills.
4. **Iterate on content.** Review the draft with the user and adjust until the scope and content are settled.
5. **Name.** Derive the name from the settled content's core action. Validate against `^[a-z0-9]+(-[a-z0-9]+)*$` and check uniqueness across load locations; confirm with the user.
6. **Description.** Write trigger-first and in third person (e.g. "Use when..."), with "Use ONLY when..." gating where apt. Frontmatter is minimal: `name` + `description` only. Ask the user individually which location the new skill should go in: project `.opencode/skills/`, global `~/.config/opencode/skills/`, or alongside existing skills in `~/.opencode/skills/`.
7. **Environment (for scripted skills).** If a confirmed helper script depends on non-standard (third-party) modules, the generated skill should include the following instructions on how to run it: if an environment is already active (e.g. `VIRTUAL_ENV`, `CONDA_PREFIX`, or an active `pdm`/`uv` context), use it; otherwise ask the user which environment to run the script with, leaving the user the option to abort skill execution.
8. **Write.** Create `<location>/<name>/SKILL.md` and any confirmed helper scripts in the same folder (scripts are referenced relatively from the skill's base directory). Verify the file(s) landed and the folder name matches the skill name.
9. **Wrap up.** Remind the user to restart opencode for the new skill to be discovered. Offer what else is worth skill-ifying; if nothing reusable is found, report that plainly and stop rather than forcing a skill.

## Pitfalls

- Never force a skill from one-off work — report and stop instead.
- Never guess the location; ask each time.
- Never add helper scripts without the user's confirmation.
- The name must match both the regex `^[a-z0-9]+(-[a-z0-9]+)*$` and the folder name.
