# Registries And Volatile Facts

DGX images may come from Harbor or Artifactory. Harbor mirrors and internal image paths are operational configuration, not stable API contracts. Image tags, hostnames, port ranges, worker counts, Slurm versions, and CLI syntax can change.

When a workflow depends on one of these values:

1. Prefer the user-provided value or a currently verified value.
2. Mark copied documentation values as requiring live verification.
3. Do not assume `latest` is compatible when a versioned image is known to work.
4. Do not fetch the Confluence landing page merely because this reference contains its URL.

The informational skill should be extended whenever new DGX knowledge is general enough to be reused by other skills or workflows.
