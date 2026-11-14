# AI integration audit — 2026-11-14

## Meaning of the results

This is a source/documentation audit, not an installation test. V means the stated contract was checked against upstream source or documentation; C means local code inspection; U means unresolved or not independently verified. V does not mean Windows execution. No GPU inference, installer, downloaded model, or Wikipedia query was executed during this audit. PowerShell is unavailable in this workspace. The safe new PowerShell regression script has been authored but not executed here.

Line references below describe the inspected pre-fix files; subsequent insertions can shift them.

## Confirmed defects and disposition

- Install-Model.ps1:44–45 checked LASTEXITCODE after running an official PowerShell installer. Strata packaging/install.ps1:177–184 can successfully fall back from failed `cmd /c mklink` to a forwarding strata.cmd without clearing the native exit code. Fixed caller to check script success (`$?`), retaining terminating errors and subsequent executable resolution. Native launch still checks LASTEXITCODE.
- Install-Skills.ps1:84–85 called Contains on potentially null output from an existing empty RULES.md. Fixed with explicit string conversion.
- Install-OMP.ps1:14 and Install-Model.ps1:46 discarded process-only PATH entries while refreshing persisted values. Fixed to retain current PATH and append persisted entries. This intentionally does not deduplicate or reorder existing entries.
- OMP executable selection remains inconsistent: Install-OMP resolves omp.exe but Install-Skills invokes bare omp. An earlier wrapper/function may receive configuration. Not fixed in this narrow patch.
- Wikipedia final filenames are trusted without integrity validation; minimum new-download size cannot prove a valid archive. Not fixed.

## Coverage ledger

### Install-OMP.ps1 (all lines read)

| Lines | Command and arguments/defaults | Status |
|---|---|---|
|2–5|CmdletBinding, StrictMode Latest, ErrorActionPreference Stop|C; Windows behavior not executed|
|6–7,15–17|Get-Command omp.exe -CommandType Application -ErrorAction SilentlyContinue; missing executable rejection|C; does not detect cmd-only installations|
|8–10|Unique temp .ps1; Invoke-WebRequest official https://omp.sh/install.ps1 -OutFile|V official URL and installer; U current downloaded payload execution|
|11|Call installer with -Binary|V upstream parameter; installation defaults LOCALAPPDATA/omp, PI_INSTALL_DIR override supported|
|12–13|Script success check and finally Remove-Item|C|
|14|Persisted User/Machine PATH refresh|C; process-path preservation fixed|
|18–19|omp.exe --version; LASTEXITCODE|V flag; U installed binary run|

Upstream installer warns that earlier PATH installations remain selected. It also configures a bash shell and can replace malformed existing settings JSON; absolute preservation of all settings cannot be promised.

### Install-Skills.ps1 (all lines read)

|Lines|Command and arguments/defaults|Status|
|---|---|---|
|7–19|LOCALAPPDATA/OMP-Skills; mkdir; git clone --depth 1 URL destination; keep existing .git|C syntax and rerun inspection; existing origin/content not validated|
|20–23|K-Dense-AI/scientific-agent-skills and claude-scientific-writer URLs|V upstream repositories|
|25–40|Education v3.1.0 portable ZIP; Expand-Archive; expected agent-skills/; Move-Item; temp cleanup|V pinned release documents archive/layout and 165 skill directories; U downloaded artifact runtime|
|42–46|science/skills, writer/skills, education/agent-skills directory checks|V layout; existing checkout may differ|
|47–54|omp config get skills.customDirectories --json; value field; union; config set JSON|V OMP schema and JSON result shape|
|56–58|config set skills.enabled true; skills.enableSkillCommands true|V settings types|
|60–75|omp skill list --json; skills[].filePath; check immediate child SKILL.md files|V CLI output; C enumeration|
|79–82|omp config path; agent directory/RULES.md|V directory semantics|
|84–85|Get-Content -Raw; Contains tag|C; empty-file defect fixed|
|86–95|Add-Content UTF8 rules block|C; instructions do not prove model compliance|

OMP config set can be overridden by project/environment settings. These scripts do not read back effective settings after writes.

### Install-Reference.ps1 (all lines read)

|Lines|Command and arguments/defaults|Status|
|---|---|---|
|3,8–11|LOCALAPPDATA/OpenZIM/archives; resolve uv.exe uvx.exe omp.exe; mkdir|C|
|15–16|uvx openzim-mcp==3.4.0 --help|V uvx package execution and OpenZIM CLI; U pinned version Windows binary dependencies|
|17–20|omp config path; PASEO_HOME else USERPROFILE/.paseo/config.json|V upstream paths|
|21–22|uv run --no-project python configure_local.py --agent-dir --paseo-config --uvx --omp --zim-dir|V uv mechanism; C five arguments agree with helper|
|24|wikipedia_en_all_nopic_2026-06.zim|U availability and official checksum not established in this audit|
|28–31|PSDrive.Free plus partial file bytes; 55GB threshold|C approximate capacity check, not exact archive validation|
|35–36|curl.exe --fail --location --retry 3 --continue-at - --output PART URL|C syntax; U independent official curl option verification in this pass|
|37–39|40GB minimum; final-file existence bypass|C inadequate integrity validation|
|42|Registration success message|C; no actual MCP query|

uvx caches disposable environments. Official uv documentation distinguishes tool execution from durable tool installation; clearing cache can break the configured offline launch. Registration does not prove offline readiness.

### configure_local.py (all lines read)

|Lines|Operation/configuration arguments|Status|
|---|---|---|
|14–20|UTF-8-sig JSON object read|C; unknown fields preserved|
|23–33|mkstemp in target parent; fdopen UTF8; json.dump; os.replace; unlink cleanup|C per-file atomic replacement; Python API docs not individually reopened|
|36–46|mcpServers.openzim; type stdio; command uvx; args --offline openzim-mcp==3.4.0 ZIM_DIRECTORY|V OMP schema and positional directory; U pinned bridge Windows startup|
|49–60|agents.providers.omp; enabled true; command [absolute omp]|V pinned Paseo beta schema|
|50–52|setdefault nested agents/providers|C malformed nested types fail without writing, but diagnostic can be AttributeError|
|63–70|Five required argparse Path options|C agrees with caller|
|71–76|Validate both merges then replace two files|C not transactional across both files; second filesystem failure can leave first changed|

Existing OMP disabledServers configuration can still disable openzim. The helper does not check this.

### Connect-LocalModel.ps1 and configure_model.py (all lines read)

|Location|Command/arguments/configuration|Status|
|---|---|---|
|PS3–9|Ports 8080/8095; Get-Command omp.exe/uv.exe; config path|V port conventions/config path; C resolution|
|PS11–12|uv run --no-project --with PyYAML python helper --agent-dir DIR --port PORT|V uv mechanism; C argument agreement; U dependency runtime|
|PS15–21|config get modelRoles --json; preserve roles; replace default; config set modelRoles JSON|V OMP schema|
|Python12–30|providers.local-inference; baseUrl localhost/v1; openai-completions; auth none; supportsDeveloperRole false|V OMP model schema|
|Python21–24|reasoning true; input text; contextWindow32768; maxTokens4096; zero costs|V accepted schema; U actual model capabilities/configuration|
|Python33–42|safe_dump YAML and atomic file replace|C values preserved; comments/format not preserved|
|Python45–62|models.yml before models.yaml; legacy models.json preservation/import|V upstream precedence|
|Python65–72|First data[].id, require nonempty string and no CRLF|C does not verify intended quantization/model or uniqueness|
|Python80–85|urllib /v1/models timeout10; save; print selector|V endpoint convention; U real server response|
|PS23|Reports default set|C effective override not checked|

### Install-Model.ps1 (all lines read)

|Lines|Command and all supplied arguments/defaults|Status|
|---|---|---|
|3–7|Hardware enum NvidiaSingle/NvidiaDual/Intel; timeout1–1440/default30m|C|
|11–20|Get-Process xestrata-cli; Get-NetTCPConnection -State Listen; reject port8095|C prevents intentional duplicate/start or shutdown; U Windows cmdlet runtime|
|24–27|xestrata-cli --setup --family gyro --model Gyro-S --context 32768 --vision no --yes --no-start|V all flags in XeStrata parser; U real preparation|
|28–32|Check idle; Start-Process exe -ArgumentList --yes,--port,8095 -PassThru|V flags and newest-config default in upstream; U Windows process lifecycle|
|35–39|nvidia-smi.exe --query-gpu=index --format=csv,noheader; require1/2 GPUs|C; U official NVIDIA flag docs not individually consulted|
|40–48|Official latest/download/install.ps1; script invocation; PATH refresh; strata.cmd lookup|V official installer path/layout; stale exit and PATH defects fixed|
|49–53|strata launch --family qwen --context 32k --access local --vision off --yes --no-tui|V all flags;32k→32768; local binding; no-tui returns after serving|
|50|Dual --model iq3_xxs --gpu-roles 0=main,1=helper|V aliases and role syntax; U hardware|
|51|Single --model iq2_xs|V alias; U hardware/memory behavior|
|54|Port8080|V upstream default|
|56–67|LOCALAPPDATA/XeStrata-Setup; exactly one exe; ProgramFiles/7-Zip/7z.exe; latest release API asset regex|C; custom/per-user7-Zip path unsupported; U current artifact layout|
|68–82|Unique temp; archive and SHA256SUMS download; exact filename match; Get-FileHash; 7z x -oDIR ARCHIVE -y|C integrity logic; U official7-Zip flag manual not independently checked|
|79–84|Extract directly into destination and require exactly one exe|C interrupted extraction leaves folder; rerun refuses incomplete folder|
|94–105|Refresh/HasExited; /v1/models timeout3 every5s; deadline|C HTTP success does not prove intended model or generation|
|105–106|Timeout leaves process; invoke connector|C Intel full rerun refuses running process; separate connector recovery is required|

## Authoritative sources actually consulted

- OMP source snapshot `20797b8941dc12c46489f696ad5d1c74b384aa93`: scripts/install.ps1, docs/settings.md, docs/models.md, docs/mcp-config.md, packages/coding-agent/src/cli/skill-list.ts.
- Strata source snapshot `13eedf552417a6a791a7d13c6597e24300ee3a09`: packaging/install.ps1, strata_cli/launch/cmd.py and launch settings.
- XeStrata source snapshot `721afe51f223fe5e60470a06a22c9961c7625fa8`: setup.py and windows/launcher/Core/Setup.fs. installed_configs sorts by modification time; --yes starts newest config after preparation.
- https://github.com/GarethManning/education-agent-skills/releases/tag/v3.1.0
- https://github.com/getpaseo/paseo/blob/v0.16.0-beta.2/docs/custom-providers.md
- https://cameronrye.github.io/openzim-mcp/docs/installation/
- https://docs.astral.sh/uv/concepts/tools/
- https://docs.astral.sh/uv/concepts/cache/
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-content?view=powershell-7.5
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-7.5

## Tests and remaining evidence

New test-ai-regressions.ps1 extracts production AST fragments and tests an existing empty/nonempty RULES.md, retention of process-only PATH in both scripts, successful installer simulation leaving native exit17, and throwing installer simulation. It uses only temporary files and mocks; it has NOT been run in this workspace because pwsh is absent. It does not download or execute vendor software.

Still needed: Windows CI execution of that test; consistent OMP executable regression; partial archive corruption checks; offline OpenZIM startup/query against a small known archive; actual Windows paths with spaces/non-ASCII; interrupted XeStrata recovery; real model identity, completion and tool-calling verification. No full installation or hardware success is claimed.

## Windows CI correction

Run 43602320577 exposed that casting inside the conditional branch did not normalize the assigned empty-file result. The cast now wraps the entire conditional subexpression, so the final assignment always receives a string. The existing empty/nonempty source-fragment regression is retained unchanged; this correction still requires its next Windows CI execution.

## Follow-up correction: durable reference bridge and archive integrity

The earlier unresolved OMP-selection/cache/integrity findings above are corrected
in source, not claimed hardware-validated. Install-Skills now resolves the same
`omp.exe` application as the other stages, rather than permitting a function or
wrapper named `omp`. Install-Reference uses `uv tool install --python 3.12
openzim-mcp==3.4.0` in dedicated `UV_TOOL_DIR`/`UV_TOOL_BIN_DIR` locations, restores
both environment variables, checks the installed executable with `--help`, and
registers that absolute executable with the archive-directory argument. No uv
cache or package-resolution step is needed at MCP launch. This changes only the
exact legacy configuration previously generated by this setup; custom MCP entries
remain protected. Registration follows successful SHA-256 validation against the
fresh official `.zim.sha256` sidecar, for both resumed downloads and existing
final files. Mismatching files are preserved and rejected rather than overwritten.

Sources: OpenZIM official installation guide
https://cameronrye.github.io/openzim-mcp/docs/installation/ ; uv CLI/environment
references https://docs.astral.sh/uv/reference/cli/ and
https://docs.astral.sh/uv/reference/environment/ ; Kiwix sidecar convention
https://hub.kiwix.org/weblog/2026/03/question-time-q1-2026/ ; Get-FileHash
https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash

Validation: 27 Python unit tests passed locally, including exact legacy MCP
migration and custom-entry rejection. This is not Windows installer execution.
The web fetcher could not retrieve the specific June 2026 checksum sidecar, so
its current availability and content remain unverified; installation fails closed
if unavailable. Actual Windows bridge installation/startup, offline query against
a ZIM, and full 49 GiB archive hashing remain unexecuted. Dedicated tool placement
and PowerShell checksum branches need Windows mock/runtime CI before claiming
those execution paths passed.

### Follow-up on empty-file regression

Diagnostic CI run 43602743698 showed genuine PowerShell cmdlets, the expected outer-cast AST, zero file bytes, and a null assignment result. The precise reason for that result has not been established; the earlier statement that branch casting alone explained the failure was not proven. Production now reads existing text through IO.File.ReadAllText and explicitly normalizes null after initialization. The regression executes the complete marked initialization block for missing, empty, and nonempty files, and reports source/expected/actual values if it fails. This change awaits Windows CI execution.
