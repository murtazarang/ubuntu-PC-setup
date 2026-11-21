# Local AI: Hermes Agent and llama.cpp

The installer uses stock llama.cpp **b12359** and Nous Research Hermes Agent **v0.23.3**, installed with Nous's native scripts. The Hermes Webapp is enabled at `127.0.0.1:9121`. The model endpoint is at `127.0.0.1:8081`. The setup does not open a LAN listener, configure phone access, install WSL, or require a cloud account.

| Hardware | Text model | Context per session | Model files |
| --- | --- | ---: | ---: |
| RTX 3080 10 GB + 40 GB RAM | NVIDIA Nemotron 3.5 Bolt 74B-A9B, CUDA | 131,072 | 22 GB |
| Arc B580 12 GB + 32 GB RAM | NVIDIA Nemotron 3.5 Bolt 74B-A9B, Vulkan | 131,072 | 22 GB |
| 2× RTX 3060 12 GB + 64 GB RAM | ISTA Qwen3.8 Flash-Next GSQ-RCO Q2_0, CUDA layer split | 262,144 | 66.4 GB across both shards |

Use **Start Local AI** from the Windows desktop or Ubuntu application menu. It waits for the selected model, then opens the official Hermes browser workspace. Use **Stop Local AI** to release the model memory. That does not delete chats, models or other data. Do not run an existing image model at the same time if it competes for memory. The installed text profiles do not include vision projectors or an image generator.

The launchers use one slot, explicit context, and the upstream model's tool template. MoE routing weights can use system RAM and the Flash-Next lookup table is resident in host memory. The profile must leave 12 GiB for Windows; no SSD streaming, paging-based fallback, or silent 64K reduction is configured. The OS remains responsible for paging policy. No speed at 128K or 256K is guaranteed. Prompt and output share the advertised context, and Hermes can summarize a conversation before it fills that window. The two 3060s do not behave like one 24 GB GPU.

## Writing, education, and Wikipedia

The setup installs the complete pinned K-Dense Scientific Agent Skills, K-Dense Claude Scientific Writer, and Gareth Manning Education Agent Skills source trees, including referenced files and assets. The inventory includes 422 definitions before resolving mirrors. Hermes uses its own skill loader, not OMP or the author's harness. Install does not configure optional remote tools, keys, or cloud APIs mentioned in those skills. Use the native Hermes file and terminal tools inside a workspace for local document or website tasks. Optional converters and scanned-PDF OCR are separate capabilities, not guaranteed by the skills alone.

Try: **“Use Offline Wikipedia to find the article on photosynthesis, read the relevant section, and cite the article title and the snapshot date.”** Hermes runs OpenZIM MCP locally over stdio and reads the June 2026 English no-pictures snapshot. It does not use embeddings, a reranker or a proxy. The archive is about 49 GiB. Reuse its verified final file or resume the existing `.part` from the same directory. The bridge retrieves source text; that is not a guarantee that the answer is correct.

- Windows: the default archive directory is `%LOCALAPPDATA%\OpenZIM\archives`; `Setup.ps1 -ArchiveDirectory` can specify another location.
- Ubuntu: the default is `~/.local/share/kiwix-mcp/archives`; set `KIWIX_ARCHIVE_DIR` to reuse another directory.

## Existing PCs

Use [the Windows migration](../windows/MIGRATE-AI.md) or the Ubuntu `migrate-existing-ai.sh` command in the [main README](../README.md#existing-ubuntu-pcs-ai-migration-only). The existing-PC path protects the archive and any partial first and inventories the old components. Its legacy deletion prompts identify the paths before changes. The fresh installer does not call those helpers. Don't confirm a list that includes something you want to keep. The setup does not uninstall your independently installed software or existing image-generation stack.

## Verification

In source verification, Hermes v0.23.3 resolved all 422 installed definitions plus Offline Wikipedia against the pinned repositories. Its real MCP client queried OpenZIM 3.4.0 over stdio and retrieved the expected article from the official small climate-change test archive. That test did not run inference, the Webapp, or the full corpus.

A successful model launch checks the assigned model, single context slot, tool template, and actual context returned by llama.cpp. If it won't start, inspect the engine log under the managed local-AI directory (Windows: `%LOCALAPPDATA%\PCSetup\local-ai`; Linux: `${XDG_DATA_HOME:-$HOME/.local/share}/pc-setup/local-ai`). Confirm the intended GPU and use the Wikipedia example above in the Webapp. This doesn't establish long-context throughput. None of the three GPU profiles should be described as a measured 50 tok/s configuration.

Sources: [Hermes installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation), [local provider configuration](https://hermes-agent.nousresearch.com/docs/user-guide/local-models), [skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills), [MCP](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp), [llama.cpp release](https://github.com/ggml-org/llama.cpp/releases/tag/b12359), [Bolt checkpoint](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-GGUF), and [Flash-Next Q2_0](https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF).
