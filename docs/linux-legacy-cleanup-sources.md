# Linux old-stack cleanup scope

Existing-PC migration only. The replacement is installed **after** confirmed old-stack removal. Fresh setup does not invoke cleanup.

Identified directories are printed before a separate irreversible confirmation; deletion includes edited skills, settings and histories. Wikipedia and replacement-stack paths are protected. Shared package caches and unrelated directories are not deletion targets. Linked roots and custom broad overrides stop cleanup rather than widening scope.

Source evidence:

- Original repository `configure-skills.sh`, commits `da19d04`, `fac0e5a`: `~/.local/share/omp-skills/{scientific-agent-skills,claude-scientific-writer,education-agent-skills}`.
- OMP `packages/utils/src/dirs.ts`: default `~/.omp`; explicitly set `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME` each use the `omp` child. Profiles are contained beneath these roots. Nondefault `PI_CONFIG_DIR` / `PI_CODING_AGENT_DIR` are reported for ownership review, not guessed.
- Strata `c77572806996349b49995e4f98d41b5294d36a21`, `strata_control/discovery.py`, `engine_component.py`, `paths.py`: XDG config/data/state `strata` directories. No generic cache directory is guessed.
- XeStrata `721afe51f223fe5e60470a06a22c9961c7625fa8`, `serve/places.py`: XDG config/data/state `xestrata` directories.
- Paseo `0e67045c4b220162637c54ff470468fbafe201c9`, `server/src/server/paseo-home.ts`, desktop `main.ts`: `~/.paseo`, Electron `XDG_CONFIG_HOME/Paseo`. Custom `PASEO_HOME` / `PASEO_ELECTRON_USER_DATA_DIR` are reported when outside known owned roots.

Foreign Claude/Codex/Gemini skill directories discovered by OMP are not OMP-owned and are not deleted. Shared Node/Bun/uv/Hugging Face caches and unrelated user projects are retained. Unknown custom locations mean full cleanup cannot be claimed until their ownership is resolved.

Original `da19d04:install-local-tools.sh` lines 9/14 creates the dedicated `~/.local/share/omp-scientific-tools/{venv,js}` runtime; this old OMP environment is included, not global uv/Node packages. `configure-skills.sh` writes the exact `omp-skills/installed-skills.json` inventory file; that file is included without deleting unrelated siblings. Offline OMP settings parsing is restricted to known root/agent and profiles/name[/agent] positions, never arbitrary plugin payload configuration files.
