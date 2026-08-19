# Storage And Python Environments

- Keep source code and small configuration in the home directory.
- Do not put large models, datasets, caches, or artifacts in home; its capacity is limited.
- Use `/export/data/users/$USER` for persistent shared data and models.
- Use `/scratch` for temporary, local, high-throughput data and caches. Copy large NFS data to scratch when loading from `/export/data/users/$USER` is slow.
- Python virtual environments commonly live under `~/venv/` in the user workflow, but the backing location should be on the appropriate `/export/data/users/$USER` area rather than consuming home storage.
- Preserve Python/container version compatibility. For images with managed Python environments, use the documented image tag instead of silently replacing it with `latest`.

These paths and image versions are operational details; verify them live when the target environment differs.
