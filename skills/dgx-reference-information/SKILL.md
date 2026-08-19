---
name: dgx-reference-information
description: Use when a request concerns the DGX system, its head or worker nodes, Slurm, srun, Pyxis, enroot, DGX containers, GPU allocations, DGX storage, or DGX access.
---

# DGX Reference Information

This is the reusable DGX knowledge bundle. Keep downstream DGX skills thin: reference this skill by name instead of duplicating architecture, access, discovery, Slurm, storage, container, or cleanup guidance. Move broadly reusable DGX knowledge back into this skill.

## Loading Contract

- Direct invocation by name loads every file in `<skilldir>/references/`.
- A downstream skill that requires this skill loads every reference file before proceeding.
- For a clearly DGX-specific request, load every reference file.
- For an ambiguous request, ask: `This may involve the DGX environment. Should I load the complete DGX reference documentation?`
- For a clearly unrelated request, do not load the references.

## References

Read all of these when this skill is loaded:

- `<skilldir>/references/architecture-and-access.md`
- `<skilldir>/references/discovery.md`
- `<skilldir>/references/slurm-containers-and-profiles.md`
- `<skilldir>/references/storage-and-venvs.md`
- `<skilldir>/references/registries-and-volatile-facts.md`

## Reusable Tool

`<skilldir>/dgx_discovery.sh` is a head-node-local discovery helper. Copy it to a unique `/tmp/dgx-reference-information-XXXXXX/` directory on the head node, execute it there, consume its JSON Lines output, and remove the temporary directory afterward. It does not authenticate, SSH, allocate GPUs, start containers, create tmux windows, or test GPU health.
