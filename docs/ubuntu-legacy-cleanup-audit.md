# Ubuntu direct legacy cleanup

The user requested direct uninstall, not quarantine. `remove-legacy-ai.sh`
previews exact packages and runtime/model subdirectories, then `--apply` requires
`DELETE LEGACY AI` immediately before destructive work. No new backup is made.

## Source-grounded ownership

- Strata [packaging/install.sh](https://github.com/Niko1221/Strata/blob/c77572806996349b49995e4f98d41b5294d36a21/packaging/install.sh):
  XDG data `strata/terminal/<version>`, `terminal/current`, and the exact
  `~/.local/bin/strata` symlink. That recognized launcher alone may invoke
  `launch --stop`. An arbitrary executable named strata is not run/deleted.
- Strata [engine_component.py](https://github.com/Niko1221/Strata/blob/c77572806996349b49995e4f98d41b5294d36a21/strata_control/engine_component.py)
  and [discovery.py](https://github.com/Niko1221/Strata/blob/c77572806996349b49995e4f98d41b5294d36a21/strata_control/discovery.py):
  XDG components and install directories; settings may override data directories.
- XeStrata [serve/places.py](https://github.com/MistVVK/XeStrata/blob/721afe51f223fe5e60470a06a22c9961c7625fa8/serve/places.py)
  and [setup.py](https://github.com/MistVVK/XeStrata/blob/721afe51f223fe5e60470a06a22c9961c7625fa8/setup.py):
  separate XDG data/config/state; packaged model library uses data/models, packs,
  mtp. Custom `data_dir` is reported but not treated as owned merely from its name.
- XeStrata [packaging unit](https://github.com/MistVVK/XeStrata/blob/721afe51f223fe5e60470a06a22c9961c7625fa8/tools/package/xestrata.service.in)
  and docs/BUILD.md: `/usr/bin/xestrata`, packaged user systemd service.
- This repository's previous Linux installation used the Paseo deb and XeStrata
  deb, with temporary downloaded installer files removed at installer exit.
  Native `apt-get remove` uninstalls their package-owned files without autoremove.

## Boundaries and checks

Only terminal/components/install/model-library subtrees are deleted, never the
whole XDG app root. Chats, configuration, state, OMP, skills, Wikipedia, shared
HF cache and prior backups remain. Root/ancestor symlinks and mounted subtrees
are refused; child symlinks are unlinked, not followed. Recognized XeStrata user
service is disabled/stopped; package-owned running executables and processes
using a deletion subtree block removal, rather than being force-killed.

Safe temporary-directory tests cover preview, declined confirmation, direct
model removal with chat preservation/no quarantine, symlink refusal and upstream
launcher stop/unlink. No real apt uninstall or GPU runtime shutdown was tested.
