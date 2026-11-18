# Native Ubuntu: Open WebUI and Colibri

No OMP is installed or used. Run `./setup.sh desktop` as the desktop user. This installs Open WebUI 0.13.4, mcpo 0.0.20, and OpenZIM MCP 3.4.0 into isolated uv tool environments. WebUI uses CUDA 12.8 PyTorch dependencies on the NVIDIA PCs; Intel Arc B580 uses OpenVINO for embeddings and reranking. Its PyTorch CPU wheel is a library dependency, not the inference device: explicit `GPU.N` selection and preflight require the B580. Intel speech is not configured by this change. Colibri independently retains its Vulkan GPU backend. Existing skills, Wikipedia archives, and user configuration are retained.

## Daily use

1. Double-click **Colibri Serve** for text, or **Colibri Serve Image** for pictures. Starting either stops the other setup-managed model to release its RAM/VRAM. No unrelated process is killed.
2. Double-click **Open WebUI**. It starts the local WebUI and Wikipedia bridge, waits for readiness, then opens your browser.
3. On first use, create your local administrator account. No external account is required. Existing accounts and chats are not overwritten.
4. Use **Stop Colibri Serve** or **Stop Colibri Serve Image** to free memory. WebUI chats remain saved.

Desktop files may require GNOME's **Allow Launching** once. Services belong to your desktop login; there is no system service, login-password storage, automatic firewall change, public network listener, or unattended model startup.

## First-use integrations

After creating your account, run the installed migration command shown below under **Existing OMP migration**. It imports and verifies the three complete skill collections using the shared helper, then asks before removing recognized OMP runtimes. Do not remove old skills until that verification succeeds. Skill instructions alone do not provide a Python execution sandbox; locally installed science tools are retained, but their invocation from WebUI requires a supported tool integration. This setup does not silently grant remote shell execution.

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

### Existing OMP migration

After setup, double-click **Open WebUI**, create your local account, then run this exact command from any terminal directory:

```bash
bash "${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup-openwebui/migrate-openwebui.sh"
```

The installed migration script verifies complete skill imports, active connections and Wikipedia integrity first. It inventories default standalone OMP, the official `PI_INSTALL_DIR` override if currently set, and the official package in Bun/npm global installations. Off-PATH custom directories whose original override is no longer available cannot be discovered automatically; restore that variable before migration. Package-manager uninstall is used for linked development packages, never recursive deletion of their source checkout. Type `REMOVE OMP` to remove only the displayed runtimes. Unknown installations or changed identities stop cleanup with their exact paths; they are never silently deleted. The script verifies absence again afterward. All skill files, custom settings, chats, Wikipedia, Bun, Node and unrelated packages are retained. Close OMP before running it.

Sources: https://omp.sh/install, https://bun.sh/docs/pm/cli/pm, https://bun.sh/docs/pm/cli/remove, https://docs.npmjs.com/cli/v11/commands/npm-uninstall/ .

See [shared verification and skill interoperability limits](openwebui-verification.md).
Intel embeddings/reranking references: https://www.sbert.net/docs/sentence_transformer/usage/efficiency.html and the tagged Open WebUI `routers/retrieval.py` native backend/model-kwargs forwarding. Setup probes native embedding and reranking inference; launch rechecks exact B580 availability. No B580 execution has been performed in the development environment.

### Approved retrieval defaults

Fresh configurations use `BAAI/bge-small-en-v1.5` embeddings and `cross-encoder/ms-marco-MiniLM-L6-v2` reranking, with token-based chunks of 400 and overlap of 50. Existing retrieval configurations and indexed knowledge are preserved; changing embedding models requires deliberate reindexing, not silent reuse of old vectors. Fresh environment defaults initialize these settings; the shared first-use helper verifies active persisted settings and stops on conflicting existing choices without changing them. B580 installation probes these exact model IDs on OpenVINO GPU; NVIDIA remains CUDA.
