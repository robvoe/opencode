# SKILL.md Format (Shape Guide)

Single source of truth for what a generated SKILL.md looks like. Official rules: https://opencode.ai/docs/skills/

## Frontmatter

Must start with a `---`-delimited YAML block. Only emit recognized fields:

- `name` (required) — 1–64 chars, lowercase alphanumeric with single hyphen separators, no leading/trailing `-`, no `--`, equals the folder name. Regex: `^[a-z0-9]+(-[a-z0-9]+)*$`
- `description` (required) — 1–1024 chars, third person, trigger-first ("Use when..."), with "Use ONLY when..." gating where apt
- `license`, `compatibility`, `metadata` (optional, string-to-string map)

Never emit unknown fields — they are silently ignored by opencode.

## Body shape

No rigid template — structure follows the skill's job. Typical spine:

- H1 title (optional but common)
- Opening line: what the skill does / when it activates
- Procedural body — imperative or headed sections as the job demands
- Companion files referenced with `./` or `<skilldir>/`

## Companion files

- Helper scripts, e.g. `<skilldir>/send.sh`
- Format spec docs, e.g. `<skilldir>/skill-format.md`
- `agents/openai.yaml` — display metadata (`interface.display_name`, `interface.short_description`); `policy.allow_implicit_invocation: false` only when the skill gates model invocation, and it must stay in sync with the SKILL.md
