# Open WebUI integration verification

## Audited native interfaces

The setup targets [Open WebUI v0.13.4](https://github.com/open-webui/open-webui/tree/v0.13.4), using its authenticated skill-import, provider, image-connection and tool-server APIs. It does not disable authentication or replace the WebUI interface.

The three complete source checkouts are pinned in `openwebui_skills.py`. They contain **422 skill definitions and 3,968 original files**, including mirrored definitions between collections. Imports keep distinct names and IDs and preserve original file bytes, references and binary assets. Full repositories, including material outside individual skill directories, remain on disk. Existing different imports and customized checkouts are not overwritten.

### Known skill interoperability limitation

`scientific-agent-skills/skills/hypogenic/SKILL.md` references `../hypothesis-generation/SKILL.md`. WebUI's native skill-file reader does not traverse between separate imported packages. The separately imported hypothesis-generation skill is available by its native manifest ID/name, but that relative link is not automatically redirected. No skill content or link has been rewritten. Importing instructions/assets also does not install or prove the operation of every optional program, API or service described by them.

## Tests actually performed

`tests/openwebui_runtime_smoke.py` uses disposable accounts and data directories with the released WebUI application, separately installed mcpo/OpenZIM, and an official small ZIM test archive. It verifies all 422 imported definitions, all 3,968 files, active state and supported metadata, then repeats the import. It exercises a streaming chat tool call through real mcpo and OpenZIM and checks the resulting persisted answer. A simulated image-model endpoint verifies native image request parameters and exact stored PNG bytes.

The protocol CI environment uses CPU dependencies **only for testing**. Its text/image backends are simulated. It is not a GPU benchmark or a test of production model inference. Windows migration fixtures use fake program files and processes, not actual OMP uninstallation. The full user Wikipedia archive, physical GPUs, real model throughput, and optional skill tools have not been tested here.

For mcpo 0.0.20, the verified compatibility pins are MCP 1.30.0 and FastAPI 0.115.12. OpenZIM 3.4.0 runs in a separate Python 3.12 environment because its MCP dependency is newer.

## Migration safety

Before offering removal of the old OMP program, migration rechecks the complete Wikipedia archive against the installer's publisher-checksum verification record and imports/reads back the skills and local connections. It then asks for confirmation of the exact program path. Original skills, configuration, conversations and Wikipedia remain untouched. If verification fails, no OMP removal is offered.

NVIDIA production setup selects CUDA dependencies for WebUI supporting models and verifies WebUI actually selects CUDA. Colibri retains its existing Vulkan configuration. CUDA PyTorch alone does not prove Faster Whisper's separate cuBLAS/cuDNN requirements are satisfied. Intel WebUI supporting-model selection remains explicitly pending rather than silently falling back to CPU.
