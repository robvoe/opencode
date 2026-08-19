# DGX Architecture And Access

## Stable Model

The DGX environment has one externally reachable head node and one or more worker nodes. GPU work runs on workers through Slurm; direct worker access is not assumed. The head node is the entry point for SSH, Slurm commands, staging helpers, and tmux coordination.

The local SSH alias `dgx` and worker aliases such as `dgx-node01` are conveniences, not universal requirements. Authentication and transport are separate concerns.

## Access Contract

1. Check whether a local `dgx` SSH configuration exists.
2. If it exists, try `ssh dgx`.
3. If authentication is missing or expired, ask the user to run the interactive local command `ekca-client-osum`, then retry `ssh dgx`.
4. If no `dgx` alias exists, ask which documented DGX transport to use. Do not confuse the transport wrapper/CLI with `ekca-client-osum`; authentication is required for either route.
5. Do not require worker SSH aliases for Slurm-based discovery or GPU diagnostics.

For non-interactive control, discovery, staging, and polling connections, use
`ssh -o ClearAllForwardings=yes dgx ...` (and the equivalent `scp` option).
The local alias may define forwards that are already occupied; those warnings
are unrelated to head-node reachability and must not be treated as an access
failure. Do not alter or kill the processes using those forwards.

The exact transport details and hostnames can change. Verify them against current operational documentation when needed.

## Passive Documentation Source

DGX Confluence landing page: https://mam-confluence.1and1.com/spaces/TDATA/pages/572337463/DGX

This link is a passive reference only. Do not fetch it automatically during ordinary loading of this skill. Use it only when the user asks for current documentation or a needed detail is not present here.
