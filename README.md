# Ubuntu Desktop setup for three PCs

> **Status:** the scripts have syntax, static and isolated configuration tests only. They have not been run through an Ubuntu 26.04.1 live install, GNOME session, real NVIDIA/Intel GPU, or gaming workloads. Check each stage on a physical PC. Do not run the disk-conversion or HDD formatting stages until their device and mount checks match your system.

Targets: Ubuntu Desktop 26.04.1 on the requested three PCs, UEFI, unencrypted Btrfs root, Timeshift on the SSD, proprietary NVIDIA driver on the 3080/3060 systems, Intel graphics on the B580 system. All passwords are entered locally and are not in this repository.

## 1. Install Ubuntu from USB

1. Boot the official Ubuntu 26.04.1 Desktop USB in **UEFI** mode. Back up anything you want to keep. The selected SSD will be erased. Check model, serial and size rather than assuming an NVMe number.
2. Choose manual installation. On the selected 512 GB NVMe create a GPT with a FAT32 EFI system partition at `/boot/efi` (1 GiB), an ext4 `/boot` (2 GiB), and a Btrfs root `/`. A separate Linux swap partition can prevent a swapfile inside `@` from blocking Btrfs snapshots; allocate it before the root partition if desired. Set Ubuntu user to `main` and enter the Ubuntu password locally. Do not enable encryption.
3. Finish the installation and choose **Continue Testing**, not Restart. Open a terminal and obtain this repository (`sudo apt-get update && sudo apt-get install -y git`, then `git clone https://github.com/murtazarang/ubuntu-PC-setup.git` and `cd ubuntu-PC-setup`). Run `./prepare-btrfs-live.sh`. It checks the target mounts, devices and expected fstab format, shows the whole disk and asks you to type the exact root partition. It invokes the author's existing `--only-subvols` implementation, without encryption. If any check fails, stop instead of overriding it.
4. Reboot, log in, then verify `findmnt -no SOURCE,FSTYPE,FSROOT /` shows Btrfs and `/@`. Check `/home` uses `@home`. If not, do not proceed.

The conversion follows [the author's Btrfs project](https://github.com/murtazarang/btrfs-encrypt-root). Its current test suite does not correspond to the checked-in shell script. The author reports having used the current script successfully; this package's wrapper and live install are not yet tested on a real machine. See `notes/PLAN.md`.

## 2. System and driver stage

From your user account, in a terminal:

```sh
./setup.sh system
```

This installs Timeshift, configures Btrfs snapshots on root SSD with `@home` excluded, creates an initial snapshot, enables i386 packages, updates Ubuntu, installs graphics packages and selects the recommended proprietary (non-`-open`) NVIDIA package when NVIDIA hardware is present. It preserves an existing matching Timeshift configuration. A different existing configuration causes a stop. The script cannot complete UEFI Secure Boot key enrollment for you if prompted.

**Reboot and log back in.** Check `nvidia-smi` on NVIDIA PCs and `vulkaninfo --summary` on all three. The Intel PC uses the Ubuntu kernel/Mesa stack. No Nouveau or experimental graphics stack is selected.

Timeshift's daily/weekly snapshots use the same Btrfs filesystem and are not a separate backup. `/home` and the separate `/boot` and EFI partitions are outside the snapshots; back them up separately. Avoid a swapfile inside `@` or `@home`, which can prevent Btrfs snapshots.

## 3. Apps, GNOME, browser and local AI

Run in a **logged-in GNOME desktop session**:

```sh
./setup.sh desktop
```

This tries the linked Stremio deb and uses the approved, officially listed Stremio Flatpak if its dependencies cannot resolve; it installs the linked Paseo package, ArtCraft Studio, Steam, Spotify, VS Code and Mailspring; removes Thunderbird after Mailspring installation; installs local writing/science tools using `uv`; installs the three GNOME extensions and Super+F2 launcher shortcut; configures Firefox extensions and uBlock; clones both complete skills packages; enables Paseo's built-in OMP provider; and configures the appropriate local model. First model download can be 58–76 GB or more and will take time. OMP defaults to the local model without requiring a K-Dense or Anthropic account; its other providers remain available if you choose to configure them later. Some bundled skills describe services that are unavailable offline; the full skills remain present and the global OMP rule directs it to local methods.

### Offline educational reference

The desktop stage registers the complete Education Agent Skills portable release alongside the two existing skill collections, and installs a local Kiwix MCP bridge for Oh My Pi. The desktop stage also downloads the Wikipedia archive (about 49 GiB). To retry or resume that download separately, run:

```bash
./download-wikipedia.sh
```

This downloads the English full-text June 2026 Wikipedia snapshot without pictures to `~/.local/share/kiwix-mcp/archives`. An interrupted download can be resumed. To use a different location, set `KIWIX_ARCHIVE_DIR` to the same directory when running both `./configure-kiwix.sh` and `./download-wikipedia.sh`. Restart Oh My Pi after configuration. Ask it to search the Kiwix archive and cite the article. The archive is a dated snapshot and source lookup does not guarantee that a model's answer is correct. Textbook PDF search is not included. No cloud account is needed for the bridge.


Models: one NVIDIA GPU → Qwen3.8-Flash-Next IQ2_XS; two NVIDIA GPUs → IQ3_XXS with one main and one helper; Intel GPU → XeStrata Gyro-S. The Intel render group change requires logging out and in, then rerunning the desktop stage. For XeStrata, a user service starts the model for setup but is not enabled at login. Stop it when gaming with `systemctl --user stop xestrata`; start with `systemctl --user start xestrata`. NVIDIA Strata provides `strata launch --status` and `strata launch --stop`. If the model is still loading when the setup times out, run `./connect-xestrata.sh 8095` once it is ready.

Paseo uses the requested `0.16.0-beta.2`, not an automatically selected stable substitute. Restart it after setup. Mailspring ID is optional; configure your email yourself. Steam and Spotify are installed but not signed in. On first Steam launch, complete Steam setup and select the current stable Proton under **Settings → Compatibility** for other titles; verify a game yourself. No online account is created by these scripts.

### Firefox configuration

Restart Firefox twice after setup. Inspect `about:policies` and confirm uBlock shows the requested filter lists and Twitch filter. Then run:

```sh
./configure-firefox.sh --release
```

This removes the one-time policy that overwrites selected lists and My filters, preserving those settings already imported by uBlock and allowing future edits. Until this command is run, those two fields reset on every browser start. Advanced mode and the VAFT resource URL remain managed. Unrelated Firefox policies are preserved; a differing existing managed uBlock configuration causes the script to stop. Existing policies are backed up before changes. Restart Firefox after releasing and check the settings again.

## 4. Format the 1 TB HDD on PC 3

On PC 3, after identifying the rotational drive with `lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS`, choose a filesystem. The script refuses non-rotational disks, disks that are mounted or outside the approximate 1 TB range, and asks you to type the exact disk name. **All data on that disk is erased.**

```sh
./format-hdd.sh /dev/sdX ext4    # replace sdX with the verified whole HDD
# or choose btrfs instead of ext4
```

It creates one partition and mounts it at `/mnt/storage` using a UUID. The choice of ext4 versus Btrfs remains yours. Neither is backed up by Timeshift snapshots on the SSD.

## Verify

```sh
./verify.sh             # local checks; model must be running
./verify.sh --model     # also submit one prompt to the local server
python3 -m unittest discover -s tests -v
```

Check Firefox add-ons/filters, GNOME shortcuts, both 3060s, Steam Proton with a real game, OMP's ability to call a local tool, and Paseo's OMP provider on the actual computers. A local endpoint responding is not proof a model, tools, gaming, or both GPUs work correctly. The scripts do not create accounts for third-party services.

## Sources and verification

- [Ubuntu installer storage](https://canonical-subiquity.readthedocs-hosted.com/en/latest/howto/configure-storage.html)
- [Ubuntu NVIDIA drivers](https://ubuntu.com/server/docs/nvidia-drivers-installation/)
- [Timeshift](https://github.com/linuxmint/timeshift)
- [Strata](https://github.com/Niko1221/Strata/blob/main/docs/INSTALL.md), [XeStrata](https://github.com/MistVVK/XeStrata)
- [Oh My Pi skills](https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md), [Paseo 0.16.0-beta.2](https://github.com/getpaseo/paseo/tree/v0.16.0-beta.2)
- [Firefox policies](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/), [uBlock managed configuration](https://github.com/gorhill/uBlock/wiki/Deploying-uBlock-Origin:-configuration)
