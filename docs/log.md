# Decision Log

## 2026-03-10 — Initial Implementation

**Decision:** Use two-stage build (Nix + Containerfile) for container image.

**Rationale:** Nix's build sandbox blocks network access, making `npm install` impossible during `dockerTools.buildImage`. By splitting into two stages—Nix for the base image, then Containerfile for npm—we get Nix's reproducibility for most packages while still being able to install Claude Code.

**Alternatives considered:**
- Pure Nix with `node2nix`: Complex, would require maintaining npm package derivations
- Pure Containerfile: Loses Nix reproducibility benefits
- Nix with `--option sandbox false`: Security concern, affects all builds

---

## 2026-03-10 — Preemptive Credential Symlinks

**Decision:** Create credential symlinks in entrypoint.sh BEFORE Claude runs.

**Rationale:** Claude writes credentials on first auth. If we let it write to tmpfs first, then try to persist, we'd need to copy and restart. By symlinking proactively, writes go directly to the persistent volume.

**Alternatives considered:**
- Post-auth copy script: Requires user intervention, error-prone
- Mount auth volume directly at ~/.claude: Works but loses the isolation benefit of tmpfs for other Claude files
- inotify-based copy daemon: Overcomplicated

---

## 2026-03-10 — Network Mode: pasta as Default

**Decision:** Use `--network=pasta` as default network mode.

**Rationale:** Pasta (successor to slirp4netns) is faster, supports more protocols, and is the default in newer Podman. Falls back gracefully.

**Alternatives considered:**
- slirp4netns: Older, slower, but more widely available
- host: No isolation, defeats purpose
- none: Breaks Claude's API access

---

## 2026-03-10 — USB Detection at Runtime

**Decision:** Scan /sys/bus/usb/devices at container start rather than hardcoding device paths.

**Rationale:** USB device paths (/dev/ttyUSB0, etc.) change when devices are unplugged/replugged. Scanning by vendor:product ID finds devices regardless of current path.

**Alternatives considered:**
- Static device paths: Fragile, breaks on replug
- udev rules on host: Requires host config changes, defeats standalone goal
- All USB passthrough: Security concern, exposes all devices

---

<!-- TODO:SECURITY — Implement egress filtering to restrict network access to known-good domains -->

<!-- TODO:FEATURE — Add VS Code devcontainer.json generation for IDE integration -->

<!-- TODO — Add aarch64 build testing to CI -->
