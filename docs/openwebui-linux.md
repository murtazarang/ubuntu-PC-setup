# Native Ubuntu: Open WebUI and Colibri

No OMP is installed or used. Run `./setup.sh desktop` as the desktop user. This installs Open WebUI 0.13.4, mcpo 0.0.20, and OpenZIM MCP 3.4.0 into isolated uv tool environments. WebUI uses CUDA 12.8 PyTorch dependencies on the NVIDIA PCs; Intel Arc B580 uses OpenVINO for embeddings and reranking. Its PyTorch CPU wheel is a library dependency, not the inference device: explicit `GPU.N` selection and preflight require the B580. Intel speech is not configured by this change. Colibri independently retains its Vulkan GPU backend. Existing skills, Wikipedia archives, and user configuration are retained.

## Daily use

1. Double-click **Colibri Serve** for text, or **Colibri Serve Image** for pictures. Starting either stops the other setup-managed model to release its RAM/VRAM. No unrelated process is killed.
2. Double-click **Open WebUI**. It starts the local WebUI and Wikipedia bridge, waits for readiness, then opens your browser.
3. On first use, create your local administrator account. No external account is required. Existing accounts and chats are not overwritten.
4. Use **Stop Colibri Serve** or **Stop Colibri Serve Image** to free memory. WebUI chats remain saved.

Desktop files may require GNOME's **Allow Launching** once. Services belong to your desktop login; there is no system service, login-password storage, automatic firewall change, public network listener, or unattended model startup.

## First-use integrations

After creating your account on a fresh installation, run the import-only `finish-openwebui.sh` command below. It verifies the complete skill collections and Wikipedia connections without legacy discovery or cleanup. Existing PCs use the separate migration entry point. Skill instructions alone do not provide a Python execution sandbox; shared science tools are not removed; the old setup-specific `omp-scientific-tools` environment is removed by existing-PC migration. Running science tools from WebUI requires a supported tool integration. This setup does not silently grant remote shell execution.

The shared import helper configures the local connections after signing in. For inspection in Open WebUI's administrator settings:

- Connections: OpenAI-compatible URL `http://127.0.0.1:8000/v1`, key `local`. The initial environment config supplies this for a new WebUI database. Existing stored connection settings take precedence and remain unchanged.
- Tools / external OpenAPI: Wikipedia URL `http://127.0.0.1:8002`; use the generated key in `~/.local/share/pc-setup-openwebui/mcpo-key`. Keep this local key private. Select the Wikipedia tool in your chat. The archive remains in `~/.local/share/kiwix-mcp/archives` (or your configured `KIWIX_ARCHIVE_DIR`).
- Images: choose the OpenAI image-generation engine and local Colibri image API `http://127.0.0.1:8001/v1`; use the actual model ID returned by that running server's `/v1/models`, not a guessed name. Image inference still needs hardware verification.
- Web search: choose DuckDuckGo/DDGS if you want live web searching; this uses the Internet, unlike Wikipedia.

No complete GPU inference, large archive download, browser signup, or real model tool call has been executed in the test environment. Generated service/desktop configuration is unit tested; full first-use configuration is still interactive.

## Diagnostics

```bash
systemctl --user status pc-setup-openwebui pc-setup-wikipedia
journalctl --user -u pc-setup-openwebui -u pc-setup-wikipedia -n 80
journalctl --user -u pc-setup-colibri-serve -n 80
```

## Authoritative references used

- https://docs.openwebui.com/getting-started/quick-start/ (native Python installation and persistent data)
- https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-openai-compatible/
- https://docs.openwebui.com/features/workspace/skills/
- https://github.com/open-webui/mcpo/blob/main/src/mcpo/__init__.py (host/port/config/API-key CLI)
- https://github.com/cameronrye/openzim-mcp (directory positional argument)
- https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html
- https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html (Conflicts and ordering)
- https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html (argument escaping)

PyTorch backend selection: https://docs.astral.sh/uv/guides/integration/pytorch/ (`--torch-backend cu128`).

### Existing-PC migration (separate from fresh setup)

Run as your logged-in Ubuntu desktop user, without sudo:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/migrate-existing-ai.sh)
```

You can append `NvidiaSingle`, `NvidiaDual`, or `Intel` if automatic hardware detection is unavailable. This dedicated path provisions only the replacement AI stack and missing AI prerequisites. It reuses or resumes Wikipedia, prepares the complete skill collections and models, starts Open WebUI, and waits for you to create/sign in to its local account. It does not run desktop/system setup, alter drivers, or install unrelated apps.

The migration inventories/protects Wikipedia and any existing new-stack data, then explicitly confirms removal of the old runtimes, old skill copies and old-owned settings/history/caches BEFORE installing replacements. Confirmed custom edits and additions inside old roots are deleted too. Unknown/shared paths block cleanup instead of being guessed disposable. Declining cleanup stops the process; a later installation failure cannot restore deleted data. Wikipedia and unrelated/new-stack data remain protected.

If provisioning already completed, resume verification and cleanup from any terminal directory:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/migrate-existing-ai.sh)
```

OMP discovery covers the default standalone path, the official `PI_INSTALL_DIR` override if set, and the official package in Bun/npm global installations. Off-PATH custom directories whose override is no longer available cannot be discovered automatically; restore that variable before migration. Unknown paths stop cleanup. Linked development packages are uninstalled through their package manager, never by recursively deleting the source checkout. Close OMP before starting cleanup.

### Fresh installation first use

Fresh setup downloads/configures only the new stack; it does not inventory or remove legacy applications. After opening Open WebUI and creating your local account, run:

```bash
bash "${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui/finish-openwebui.sh"
```

This imports and verifies the complete skills and connections without cleanup.

Sources: https://omp.sh/install, https://bun.sh/docs/pm/cli/pm, https://bun.sh/docs/pm/cli/remove, https://docs.npmjs.com/cli/v11/commands/npm-uninstall/ .

See [shared verification and skill interoperability limits](openwebui-verification.md).
Intel embeddings/reranking references: https://www.sbert.net/docs/sentence_transformer/usage/efficiency.html and the tagged Open WebUI `routers/retrieval.py` native backend/model-kwargs forwarding. Setup probes native embedding and reranking inference; launch rechecks exact B580 availability. No B580 execution has been performed in the development environment.

### Approved retrieval defaults

Fresh configurations use `BAAI/bge-small-en-v1.5` embeddings and `cross-encoder/ms-marco-MiniLM-L6-v2` reranking, with token-based chunks of 400 and overlap of 50. Existing retrieval configurations and indexed knowledge are preserved; changing embedding models requires deliberate reindexing, not silent reuse of old vectors. Fresh environment defaults initialize these settings; the shared first-use helper verifies active persisted settings and stops on conflicting existing choices without changing them. B580 installation probes these exact model IDs on OpenVINO GPU; NVIDIA remains CUDA.

Migration also refuses cleanup if an unregistered `.zim` archive or `.zim.part` download is found inside an old deletion root. It prints the path and leaves it untouched; relocate the corpus deliberately and configure its retained location before retrying. It does not silently move or delete an archive.
