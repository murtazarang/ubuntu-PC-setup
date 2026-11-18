# Local AI desktop (native Windows)

The Desktop stage uses Colibri + Open WebUI, **not Oh My Pi**. Python is managed in a separate uv environment. It does not use WSL/Docker, replace drivers, configure Tailscale, or expose servers beyond localhost.

1. Run the normal Desktop setup. Existing verified model downloads and Wikipedia are reused.
2. Double-click **Colibri Serve** for text or **Colibri Serve Image** for pictures. The model loads in the background; a successful shortcut launch does not mean weights are ready. Loading errors are recorded in `text.log` or `image.log` in the setup directory. Starting one stops the other only if this setup recorded and still recognizes that process. An unrelated server occupying the port is left alone.
3. Double-click **Open WebUI**. First launch can take several minutes; its log is `%LOCALAPPDATA%\OpenWebUI-PC-Setup\webui.log`. Create the first local account in the browser. No cloud account is required.
4. Double-click **Finish Open WebUI Setup**, sign in to that local account when prompted, and wait for complete skill import and verification. All three original repositories are retained on disk, including reference files and scripts. A skill definition does not by itself execute its optional tools or make cloud APIs available.
5. Use **Stop Colibri Model** to release RAM/VRAM. No terminal has to stay open. Choose the other Serve shortcut to switch models; the Open WebUI model picker does not load/unload Colibri weights.

Full collections: K-Dense-AI scientific-agent-skills, K-Dense-AI claude-scientific-writer, GarethManning education-agent-skills. Existing OMP/custom skills and the corpus are retained until migration has been verified. No cleanup is performed by this installer.

The Wikipedia bridge is OpenZIM MCP 3.4.0 through Open WebUI's mcpo 0.0.20. WebUI 0.13.4 runs on Python 3.11. Ports: text8000, image8001, Wikipedia8002, WebUI8080; all loopback only. The fixed data directory preserves chats/accounts across reruns. Existing desktop/runtime configuration is preserved rather than reset.

## Verification boundary

Python ownership tests exercise PID-reuse and command-change guards and termination of a disposable owned process. They do not establish actual Windows install success, GPU inference, full-corpus tool use, image generation, or real model switching. Those require the target PC. Do not describe these as completed until tested.

## Sources

- [Open WebUI native Python install](https://docs.openwebui.com/getting-started/quick-start/)
- [v0.13.4 CLI host/port options](https://github.com/open-webui/open-webui/blob/v0.13.4/backend/open_webui/__init__.py)
- [v0.13.4 environment configuration](https://github.com/open-webui/open-webui/blob/v0.13.4/backend/open_webui/config.py)
- [mcpo v0.0.20 CLI](https://github.com/open-webui/mcpo/blob/v0.0.20/src/mcpo/__init__.py)
- [Skills](https://docs.openwebui.com/features/workspace/skills/)
- [Colibri v2.1.0](https://github.com/JustVugg/colibri/tree/v2.1.0)
- [psutil process identity and termination](https://psutil.readthedocs.io/en/latest/#process-class)

NVIDIA GPU supporting models are approved; PyTorch 2.9.1 CUDA 12.8 wheels are selected and CUDA availability is checked during installation and UI launch. Intel Arc B580 runs native OpenVINO embeddings and reranking with explicit GPU selection and an installation inference probe; missing GPU or CPU execution fails setup. PyTorch CPU wheels on Intel provide library/export utilities, not a retrieval inference fallback. Colibri inference still uses Vulkan. OpenZIM runs in its own Python 3.12 environment; mcpo has an isolated Python environment pinned to mcpo0.0.20, mcp1.30.0 and FastAPI0.115.12.

CUDA wheel source: https://pytorch.org/get-started/previous-versions/#v291. WebUI supporting PyTorch models use CUDA; this is not evidence that Whisper CTranslate2 or every optional tool can use the GPU. Their additional CUDA/cuDNN dependencies and hardware behavior need separate validation.

Fresh retrieval defaults use BAAI/bge-small-en-v1.5 and cross-encoder/ms-marco-MiniLM-L6-v2, tokenizer-based 400-token chunks with 50-token overlap. Existing indexes/settings are not overwritten or reindexed. First OpenVINO export/model loading may take time. Actual B580 hardware testing remains unperformed here; the installer performs the check on the target PC.
