# AI command audit follow-up — 2026-11-14

## Baseline and evidence levels

Reviewed GitHub main at `4293bf9692ff658c183e6a3264ac03e06912fdad`, specifically the current Install-Model.ps1, Install-Reference.ps1, Install-Skills.ps1 and the earlier AI ledger. The earlier ledger is a chronological record, not a current unresolved-defect list. Its statements that the Wikipedia checksum, persistent MCP installation, OMP executable consistency and empty RULES.md fix remain unimplemented or await CI are superseded below.

This pass made no installer changes and ran no installers. D = upstream documentation/source inspected; T = observed successful safe CI step; U = real integration still untested. D and T do not establish an end-to-end installation.

## Previously unresolved command documentation

| Invocation | Evidence | Remaining limitation |
|---|---|---|
| `curl.exe --fail --location --retry 3 --output FILE URL` | D: official curl manual documents HTTP failure return, redirect following, three retries for qualifying transient failures, and named output. | Retries are not a retry of every possible error and are not a total elapsed-time limit. Windows transfer not executed here. |
| `curl.exe --continue-at -` with named output | D: official manual specifies automatic resume offset from the input/output file. | Remote server must support resume; SHA-256 validation remains necessary. Full ZIM download not executed. |
| `nvidia-smi.exe --query-gpu=index --format=csv,noheader` | D: NVIDIA manual documents selective query and mandatory CSV format plus `noheader`; device indexes are driver-enumerated and may change across reboots. | This pass did not execute installed driver `--help-query-gpu` or a GPU query. The exact property listing for `index` was not independently exercised. Counting GPUs does not validate available memory or model fit. |
| `7z.exe x "-oDIRECTORY" ARCHIVE -y` | D: official 7-Zip source CLI help explicitly lists `x` full-path extraction, `-o{Directory}` output directory and `-y` yes to queries. | No actual XeStrata release extraction tested in this pass; unfamiliar artifact layout remains fail-closed. |
| `uv tool install --python 3.12 openzim-mcp==3.4.0` with UV_TOOL_DIR / UV_TOOL_BIN_DIR | D: uv environment reference documents the tool environment and executable locations; current script restores prior process variables. | Actual native Windows bridge dependencies, offline startup and article query remain U. |
| `omp config set ...` success | D: OMP config-cli.ts writes the global value but separately warns about project/environment/overlay/runtime shadowing. `config get --json` returns the effective setting value. | A successful write is not proof of effective configuration in every project. The connector currently prints a default-model success line without effective-value readback. Preserve overrides rather than silently clearing them. |

Sources:
- https://curl.se/docs/manpage.html (`--fail`, `--location`, `--retry`, `--output`, `--continue-at`)
- https://docs.nvidia.com/deploy/nvidia-smi/index.html (selective query, output options and device enumeration)
- https://github.com/ip7z/7zip/blob/main/CPP/7zip/UI/Console/Main.cpp (CLI help)
- https://docs.astral.sh/uv/reference/environment/ (`UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`)
- https://github.com/can1357/oh-my-pi/blob/20797b8941dc12c46489f696ad5d1c74b384aa93/packages/coding-agent/src/cli/config-cli.ts (`handleGet`, `handleSet`, `shadowingSource`)

The guessed 7-Zip DOC/MANUAL raw URLs returned 404; those were not evidence. The official source CLI help was inspected instead.

## CI evidence actually checked

GitHub Actions run https://github.com/murtazarang/ubuntu-PC-setup/actions/runs/43606198141, job `132481248438`, reports success for PowerShell parsing, launcher binding in Windows PowerShell 5.1 and PowerShell 7, discovery and argument tests in both shells, mocked update/model/application/Everything tests, AI/PATH regressions, SignalRGB detection, existing OMP discovery, XeStrata inventory, offline-reference/desktop safety, and isolated Python tests. This pass retrieved the job-step results directly. This is safe mocked coverage; it is not execution of any third-party installer.

Therefore the earlier ledger's pending CI statements for RULES.md, OMP consistency, reference checksum branches and dedicated tool-placement mocks are superseded by that successful run. The official Wikipedia checksum sidecar availability was separately verified in the prior coordinated pass; no full archive validation was performed by this pass.

## Remaining material integration boundaries

1. OMP effective settings can be overridden. Readback with `config get ... --json` can identify this without changing user overrides; a future patch should distinguish a globally saved value from an effective default. Skills inventory validation already checks discovered immediate-child SKILL.md entries, but is not a complete test of every imported skill or optional local tool.
2. Native Strata/XeStrata startup, quantization identity, actual inference, tool calls and memory use on the three target PCs remain untested. An HTTP `/v1/models` answer is not a generation test. The connector selects the first returned model ID; it does not prove quantization identity.
3. Existing XeStrata config handling is intentionally conservative. Multiple/mismatched configs or a running process stop rather than being overwritten. Interrupted extraction leaves an incomplete directory and requires explicit inspection; that is an actionable stop, not automatic rerun repair.
4. The persistent bridge should survive uv cache eviction by construction, but a real Windows install and offline query against a small known ZIM are still needed. The full 49-GiB Wikipedia download, hashing and real query remain unperformed.
5. Source snapshots audited for Strata/XeStrata do not prove every older packaged binary has the same inventory schema. Unexpected inventory fails closed.
6. Existing scientific/writer checkouts are preserved without origin/content verification. Global skills registration does not install every optional tool described by those skills. This is consistent with importing the complete definitions but must not be described as proving all skill actions work offline.
7. Two config files are individually replaced atomically, not as a two-file transaction. Validation occurs before writes; a filesystem failure on the second replacement can still leave the first replacement committed.

No new confirmed installer-blocking defect was identified in this bounded pass. These boundaries must not be upgraded to verified solely because command syntax or mocks pass.
