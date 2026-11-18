# Legacy configuration cleanup audit

Reviewed 2026-11-18 against integrated candidate `68bff2c`, specifically `cleanup_legacy_config.py` and its invocation from `Remove-LegacyAI.ps1`. This is a bounded configuration audit, not a claim that real Windows uninstallers or hardware were exercised.

## Commands and authoritative evidence

OMP source inspected at `b279532036313bdbdfe7a60a613e6d73a4ca8b15`:

| Operation | Source and verified meaning |
|---|---|
| `omp config path` | [config-cli.ts, handlePath](https://github.com/can1357/oh-my-pi/blob/b279532036313bdbdfe7a60a613e6d73a4ca8b15/packages/coding-agent/src/cli/config-cli.ts#L441-L443) prints `getAgentDir()`. The helper does not guess the profile directory. |
| `omp config list --scope global --json` | [handleListLayer](https://github.com/can1357/oh-my-pi/blob/b279532036313bdbdfe7a60a613e6d73a4ca8b15/packages/coding-agent/src/cli/config-cli.ts#L274-L298) reads the saved global layer, emits records with `value`, and omits unset keys. Project/effective roles are not copied into global settings. |
| `omp config set modelRoles <JSON>` | [handleSet](https://github.com/can1357/oh-my-pi/blob/b279532036313bdbdfe7a60a613e6d73a4ca8b15/packages/coding-agent/src/cli/config-cli.ts#L326-L365) parses the setting value, persists/flushes the setting, and reports the saved global value. JSON is passed as one subprocess argument, without shell evaluation. |
| `models.yml`, then `models.yaml`, then legacy `models.json` | [ConfigFile](https://github.com/can1357/oh-my-pi/blob/b279532036313bdbdfe7a60a613e6d73a4ca8b15/packages/coding-agent/src/config/config-file.ts#L150-L210) implements YAML precedence and legacy JSON migration. Cleanup does not activate a dormant lower-precedence file. |
| `uv run --no-project --with PyYAML python <helper> --omp <exe> --backup <dir>` | [uv CLI reference](https://docs.astral.sh/uv/reference/cli/#uv-run): `run` executes the command, `--no-project` disables project discovery, and `--with` supplies an additional dependency. The helper's argparse defines the two subsequent flags. This can require a package/Python download; it is not asserted to work offline. |

## Scope and preservation

Only `local-inference` with the exact historical generated provider shape and loopback port 8080 or 8095 is removed. Port 8000 (Colibri), additional provider fields, and other customizations are preserved. Matching is a conservative historical-shape heuristic, not an installation receipt proving authorship.

Before removing the provider in memory, the helper captures its single model ID. Only global role values exactly equal to that model's `local-inference/<id>` selector are removed. Different selectors, nested values, other roles and other providers remain. The backup stores the original model file and global model-role values under `PC-Setup/LegacyAI-Config-Backup`, outside deleted runtime paths. OMP itself, skill files, MCP configuration, project settings and session data are not deleted by this helper.

The replacement file is staged before roles change. Temp-file creation/write failure therefore cannot clear roles. Failure during role persistence or model-file replacement attempts to restore the saved global role map. A failed rollback remains an error, with backups retained; this is not an atomic transaction across two independent files/processes. Concurrent external config editing is not coordinated. YAML serialization can change formatting/comments, while the original file remains backed up.

## Verification performed

Reran on integrated `68bff2c`:

```
python -m unittest discover -s windows/tests -p test_cleanup_legacy_config.py -v
```

All 12 tests passed. Coverage includes exact/custom/Colibri provider discrimination, exact-role matching, real temporary filesystem JSON/YAML writes and backups, temp creation failure, failed replacement, partially failing mocked OMP write with restoration, and preservation of custom selectors.

These tests mock the OMP CLI, not filesystem writes. They do not exercise a real OMP binary on Windows, real Windows permissions, concurrent editors, or a real end-user installation. The full direct-deletion/process/reparse and Paseo uninstaller reviews are separate audit scopes.
