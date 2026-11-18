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

This tries the linked Stremio deb and approved Flatpak fallback; installs ArtCraft Studio, Steam, Spotify, VS Code and Mailspring; configures the desktop, Firefox, full skills and local document tools; and installs Colibri's built-in browser UI. It no longer installs Paseo, Strata or XeStrata. Setup downloads a checksum-verified text GGUF, resuming interrupted transfers and reusing verified local files. OMP's other providers remain available.

### Offline educational reference

The desktop stage registers the complete Education Agent Skills portable release alongside the two existing skill collections, and installs a local Kiwix MCP bridge for Oh My Pi. The desktop stage also downloads the Wikipedia archive (about 49 GiB). To retry or resume that download separately, run:

```bash
./download-wikipedia.sh
```

This downloads the English full-text June 2026 Wikipedia snapshot without pictures to `~/.local/share/kiwix-mcp/archives`. An interrupted download can be resumed. To use a different location, set `KIWIX_ARCHIVE_DIR` to the same directory when running both `./configure-kiwix.sh` and `./download-wikipedia.sh`. Restart Oh My Pi after configuration. Ask it to search the Kiwix archive and cite the article. The archive is a dated snapshot and source lookup does not guarantee that a model's answer is correct. Textbook PDF search is not included. No cloud account is needed for the bridge.


### Colibri on the three Ubuntu PCs

All three use the official Colibri v2.1.0 Linux CPU+Vulkan release, verified with its release SHA-256. No CUDA toolkit/source build is required. Existing proprietary NVIDIA or Intel Mesa/Vulkan drivers must already work (`vulkaninfo --summary`).

- RTX 3080: one Vulkan device, `COLI_VULKAN=1`.
- Two RTX 3060s: additionally `COLI_VK_DEV2=auto`, the upstream second-device expert tier. This is not a promise of 24 GB contiguous memory or measured speedup; model support, budgets and actual use of both GPUs must be verified. Upstream documents that its second-device tests do not establish performance on two real GPUs.
- Intel Arc B580: Vulkan selects a preferred discrete GPU. Check the startup log names the B580 rather than the CPU/iGPU.

Setup selects Qwen3.8-27B UD-Q4_K_M text GGUF for the RTX 3080 and Arc B580, and Qwen3.8-Flash-Next IQ2_XS for the dual RTX 3060. It imports the verified GGUF through native `coli import --mode link --no-mtp`, without copying large weights or a PyTorch conversion. Models live in `~/colibri-models/<profile>/{source,model}`. Keep the source directory: imported metadata points at its weights. Copying a verified source directory to the same relative location on another PC avoids downloading it again; rerun setup to rebuild local links. Existing customized imported metadata is preserved rather than overwritten.

Run `./configure-ai.sh NvidiaSingle`, `NvidiaDual`, or `Intel` to select explicitly; default detection recognizes the three requested PCs and otherwise stops with instructions. `COLIBRI_MODELS_DIR` can set another model root. Launch **Colibri Serve** from the desktop/app menu. GNOME may require **Allow Launching** once. It starts native `coli serve` and the modern `coli ui` (port 8790, backend 8000) together in a visible terminal. Keep it open; Ctrl+C stops the foreground process group. Existing occupied server/UI ports are not reused or killed. The shortcut applies Vulkan and the dual-GPU expert-tier flag only for NvidiaDual. No autostart or custom model-running service is installed.

The built-in UI remains available with `coli ui --models-dir "$HOME/colibri-models"` at `http://127.0.0.1:8790`; inference is loopback `http://127.0.0.1:8000/v1`. Run `./connect-colibri.sh` after the server starts to update OMP. The installed text GGUFs do **not** support image/video inputs. Model Downloads/Use in the upstream UI remain available; Linux Use switches an already-running gateway. Rerun the OMP connection helper after changing models.

Setup also downloads the native Qwen-Image-2.1 checkpoint (about 33 GB) with the same resume/hash/reuse checks, and creates **Colibri Serve Image** with a **Serve Img** icon label. It invokes upstream `coli web` directly on loopback port **8001**, using isolated Python with NumPy and Pillow. Text Serve uses **8000**. Run one at a time unless memory permits both; separate ports do not guarantee enough combined GPU/RAM capacity. Image generation is distinct from the text model's input capabilities. The image checkpoint's license limits use to research/evaluation; read its downloaded LICENSE before use. The image shortcut opens the upstream image-generation web frontend automatically. The modern `coli ui` does not implement image generation, so it is used only for text. No third desktop UI shortcut is created.

For an existing setup, first preview `./remove-legacy-ai.sh`; use `./remove-legacy-ai.sh --apply` to uninstall the known packages and directly delete the exact listed runtime/model download subtrees. It requires typing `DELETE LEGACY AI` after displaying those paths. No quarantine or new backup is created. Chat/history/config/state, shared packages, OMP/skills/Wikipedia, external models and earlier backups are preserved; external configured data folders are reported, not blindly wiped. Recognized native services are stopped; any remaining running app must be closed before deletion. Symlinked or mounted deletion roots are refused. Then run `./configure-ai.sh`. The obsolete `connect-xestrata.sh` is replaced by `connect-colibri.sh`.

Mailspring ID is optional; configure your email yourself. Steam and Spotify are installed but not signed in. On first Steam launch, complete Steam setup and select the current stable Proton under **Settings → Compatibility** for other titles; verify a game yourself. No online account is created by these scripts.

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

Check Firefox add-ons/filters, GNOME shortcuts, both 3060s, Steam Proton with a real game, OMP's ability to call a local tool, and the Colibri UI on the actual computers. A local endpoint responding is not proof a model, tools, gaming, or both GPUs work correctly. The scripts do not create accounts for third-party services.

## Sources and verification

- [Ubuntu installer storage](https://canonical-subiquity.readthedocs-hosted.com/en/latest/howto/configure-storage.html)
- [Ubuntu NVIDIA drivers](https://ubuntu.com/server/docs/nvidia-drivers-installation/)
- [Timeshift](https://github.com/linuxmint/timeshift)
- [Colibri UI](https://github.com/JustVugg/colibri/blob/v2.1.0/ui/README.md), [Vulkan/dual-device backend](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/vulkan.md)
- [Oh My Pi skills](https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md)
- [Firefox policies](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/), [uBlock managed configuration](https://github.com/gorhill/uBlock/wiki/Deploying-uBlock-Origin:-configuration)
