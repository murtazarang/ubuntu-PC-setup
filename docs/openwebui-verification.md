# Open WebUI integration verification

## Audited native interfaces

The setup targets [Open WebUI v0.13.4](https://github.com/open-webui/open-webui/tree/v0.13.4), using its authenticated skill-import, provider, image-connection and tool-server APIs. It does not disable authentication or replace the WebUI interface.

The three complete source checkouts are pinned in `openwebui_skills.py`. They contain **422 skill definitions and 3,968 original files**, including mirrored definitions between collections. Imports keep distinct names and IDs and preserve original file bytes, references and binary assets. Full repositories, including material outside individual skill directories, remain on disk. Existing different imports and customized checkouts are not overwritten.

### Known skill interoperability limitation

`scientific-agent-skills/skills/hypogenic/SKILL.md` references `../hypothesis-generation/SKILL.md`. WebUI's native skill-file reader does not traverse between separate imported packages. The separately imported hypothesis-generation skill is available by its native manifest ID/name, but that relative link is not automatically redirected. No skill content or link has been rewritten. Importing instructions/assets also does not install or prove the operation of every optional program, API or service described by them.

## Tests actually performed

`tests/openwebui_runtime_smoke.py` uses disposable accounts and data directories with the released WebUI application, separately installed mcpo/OpenZIM, and an official small ZIM test archive. It verifies all 422 imported definitions, all 3,968 files, active state and supported metadata, then repeats the import. It exercises a streaming chat tool call through real mcpo and OpenZIM and checks the resulting persisted answer. A simulated image-model endpoint verifies native image request parameters and exact stored PNG bytes.

The protocol CI environment uses CPU dependencies **only for testing**. Its Colibri text/image backends are simulated. Approved BGE embedding and MiniLM reranking run as real OpenVINO CPU inference in this disposable test, including native text ingestion and hybrid retrieval. It is not a GPU benchmark or a test of production model inference. Windows migration fixtures use fake program files and processes, not actual OMP uninstallation. The full user Wikipedia archive, physical GPUs, real model throughput, and optional skill tools have not been tested here.

For mcpo 0.0.20, the verified compatibility pins are MCP 1.30.0 and FastAPI 0.115.12. OpenZIM 3.4.0 runs in a separate Python 3.12 environment because its MCP dependency is newer.

## Migration safety

Before offering removal of the old OMP program, migration rechecks the complete Wikipedia archive against the installer's publisher-checksum verification record and imports/reads back the skills and local connections. It then asks for confirmation of the exact program path. Original skills, configuration, conversations and Wikipedia remain untouched. If verification fails, no OMP removal is offered.

NVIDIA production setup selects CUDA dependencies for WebUI supporting models and verifies WebUI actually selects CUDA. Colibri retains its existing Vulkan configuration. CUDA PyTorch alone does not prove Faster Whisper's separate cuBLAS/cuDNN requirements are satisfied. Intel B580 document embeddings and reranking use explicitly selected OpenVINO GPU execution, with errors instead of CPU fallback. Speech acceleration remains undecided.

## Intel B580 retrieval backend (review branch)

`openwebui_gpu.py` selects the OpenVINO device whose `FULL_DEVICE_NAME` identifies
B580, not a generic `GPU` alias that might select the CPU's integrated GPU. It
refuses absent or ambiguous devices. It supplies the native Open WebUI embedding
and cross-encoder backend environment fields with an explicit device ID. It does
not select speech engines, install drivers, or change Colibri Vulkan settings.

The separate model probe uses native `get_ef` and `get_rf`, executes a tiny
embedding/reranking request, and checks the compiled model's `EXECUTION_DEVICES`.
A failed load, missing compiled request, CPU execution, or a different GPU fails
the probe. It requires explicit model IDs. Fresh installations use the approved BAAI/bge-small-en-v1.5 embedding and cross-encoder/ms-marco-MiniLM-L6-v2 reranker, BGE-token chunks of 400 with overlap 50, and the author-recommended query-only prefix. Existing persistent settings/indexes are not rewritten; migration checks active settings and stops on a mismatch.
The probe's fake-object regression tests are not physical B580 tests.

Source contracts:
- [Open WebUI v0.13.4 environment backend fields](https://github.com/open-webui/open-webui/blob/v0.13.4/backend/open_webui/env.py)
- [Native retrieval model construction](https://github.com/open-webui/open-webui/blob/v0.13.4/backend/open_webui/routers/retrieval.py)
- [Sentence Transformers OpenVINO backend](https://sbert.net/docs/sentence_transformer/usage/efficiency.html#openvino)
- [OpenVINO device discovery](https://docs.openvino.ai/2026/api/ie_python_api/_autosummary/openvino.Core.html)

Existing skill repositories and `.omp` data remain preserved after the optional
verified OMP executable removal. They have not been deleted or silently moved.

Approved model sources: [BGE small English v1.5](https://huggingface.co/BAAI/bge-small-en-v1.5), [MiniLM L6 MS MARCO reranker](https://huggingface.co/cross-encoder/ms-marco-MiniLM-L6-v2). The BGE prefix is applied only to queries through native WebUI configuration, not to stored passages or reranker inputs.
