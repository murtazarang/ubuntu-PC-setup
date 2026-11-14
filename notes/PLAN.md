# Ubuntu PC setup: design and evidence

Target: Ubuntu Desktop 26.04.1, UEFI, three selected PCs; unencrypted Btrfs @/@home, Timeshift snapshots on root SSD; NVIDIA proprietary driver or Intel Mesa; requested applications and local Qwen/OMP (Intel Gyro-S; RTX 3080 IQ2_XS; dual RTX 3060 IQ3_XXS). Never write passwords or hashes into this public repository.

## Installation
Ubuntu installer does not configure Btrfs subvolumes (https://canonical-subiquity.readthedocs-hosted.com/en/latest/howto/configure-storage.html). Use Ubuntu Desktop GUI for initial FAT32 EFI, ext4 /boot and Btrfs root, then existing author's proven --only-subvols script while still in the live session, after validating mounted target and exact disks. The existing script's fstab pattern is fragile, so do not blindly invoke until checked on exact installer output. Verify boot and Timeshift before postinstall. Do not claim this is a fully automated Ubuntu installation.

## Source details
- User btrfs setup: https://github.com/murtazarang/btrfs-encrypt-root
- XeStrata low RAM maps model files and may run slower: https://github.com/MistVVK/XeStrata/blob/main/docs/DETAILS.md#less-ram-than-the-model-the-low-ram-mode
- Strata: https://github.com/Niko1221/Strata/blob/main/docs/TERMINAL_LAUNCH.md
- Paseo v0.16.0-beta.2 OMP is builtin, disabled by default: https://github.com/getpaseo/paseo/blob/v0.16.0-beta.2/docs/providers.md
- OMP 203 skills across two separate roots, preserve colliding names, no external AI APIs; use skills.customDirectories.
- uBO management: https://github.com/gorhill/uBlock/wiki/Deploying-uBlock-Origin:-configuration
- NVIDIA driver: https://ubuntu.com/server/docs/nvidia-drivers-installation/

## Verification
A Debian sandbox cannot prove 26.04 installer, actual GPU execution, GNOME session, Firefox Snap policy, services, game behavior or physical-device erasure. Never label these as tested. Test safely with mocks, bash -n, ShellCheck when available; gate real destructive or incompatible operations.
