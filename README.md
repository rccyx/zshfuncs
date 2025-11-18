# zshfuncs

I hate the mental drag of clicking through UIs, so I run almost everything from the terminal. This is a terminal-first productivity toolkit with over 200 commands covering system administration, cloud ops, dev workflows, and everyday automation that I use.

## Security & Authentication

### Fingerprint Authentication

- `fp_setup_from_scratch` - Complete fingerprint setup workflow from restart to enrollment
- `fp_mode_login_sudo` - Enable fingerprint for both login and sudo via common-auth
- `fp_mode_sudo_only` - Enable fingerprint for sudo only with direct PAM line
- `fp_mode_off` - Disable fingerprint authentication completely
- `fp_switch` - Switch primary fingerprint by wiping all and enrolling new one
- `fp_enroll_multi` - Enroll multiple fingers interactively with FZF multi-select
- `fp_enroll` - Enroll single finger with FZF picker from canonical finger list
- `fp_delete` - Delete specific fingerprint or all prints with confirmation
- `fp_nuke` - Delete all fingerprints for current user
- `fp_list` - List enrolled fingerprints for current user
- `fp_status` - Show fingerprint device status and enrolled prints for current user
- `fp_test` - Test fingerprint verification

### GPG & Encryption

- `gpg.` - Interactive GPG menu with all operations using FZF
- `gpg.gen` - Quick generate RSA4096 key with 2 year validity
- `gpg.enc` - Encrypt files for selected recipients or symmetric with multi-recipient support
- `gpg.dir` - Tar-compress directory then encrypt, supports zstd/gzip compression
- `gpg.sign` - Clearsign or detached-sign with picked secret key
- `gpg.verify` - Verify signature files with detailed output
- `gpg.export_pub` - Export public key to .asc file and copy to clipboard
- `gpg.export_sec` - Export secret key to .asc file with security warning
- `gpg.import` - Import .asc or .gpg key files with picker support
- `gpg.recv` - Locate and import keys by email or fingerprint via WKD/keyserver
- `gpg.trust` - Edit ownertrust for selected key interactively
- `gpg.dec` - Decrypt files with optional tar extraction if archive detected
- `gpg.dec_stdout` - Decrypt to stdout for piping operations
- `gpg.armor` - Convert binary to ASCII armor output to stdout
- `gpg.dearmor` - Convert ASCII armor to binary output to stdout
- `gpg.inspect` - Show recipients and packets for encrypted file
- `gpg.agent` - Agent control helper with status/restart/ssh modes
- `gpg.ls` - Fuzzy list keys with preview showing fingerprint, algo, dates
- `gpg.del` - Delete public and secret key with fingerprint confirmation
- `passenc` - Encrypt file with passphrase and shred original
- `passdec` - Decrypt file with passphrase and shred encrypted version
- `loadpg` - If the GPG daemon is fucking up, restart it.

## Network & WiFi

- `wifi` - Interactive WiFi connection with network scanner and password prompt
- `wifireconnect` - Reconnect to selected saved network
- `wifipass` - Show password for current WiFi network and copy to clipboard
- `wifiresume` - Turn on WiFi radio
- `wifikill` - Turn off WiFi radio
- `wifiqr` - Generate QR code for current WiFi network connection
- `wifi_forget` - Forget saved WiFi profile by name or selector
- `connected-devices` / `devices` - Comprehensive network device discovery with ARP, ping, NetBIOS, port scanning
- `device_deep` - Deep nmap scan of single host with OS detection
- `netspeed` - Test internet speed using speedtest-cli with clipboard copy
- `net_iface` - Detect active network interface
-

### 2FA & Passwords

- `tfa` - Interactive TOTP manager with fzf picker and oathtool backend
- `tfa.add` - Add new 2FA secret
- `tfa.use` - Generate and copy TOTP code
- `tfa.list` - List stored secrets with masked preview
- `tfa.change` - Update existing secret
- `genpass_easy` - Generate hex password (16 bytes as 32 hex chars)
- `genpass_mid` - Generate base64 alphanumeric password (32 chars)
- `genpass_hard` - Generate complex password with special characters (32 chars)

## Cloud & AWS

### S3 Operations

- `s3up` - Upload files/folders to S3 with multipart resume support and progress
- `s3down` - Download from S3 with resume support for large files
- `s3ls` - List S3 objects with FZF search and metadata preview
- `s3rm` - Delete S3 objects with confirmation, supports batch operations
- `s3buckets` - List available S3 buckets
- `s3who` - Show current AWS caller identity

### EventBridge & Scheduler

- `eb.ui` - Interactive EventBridge UI with fuzzy menus for all operations
- `eb.ctx` - Show EventBridge context (account, profile, region, bus)
- `eb.bus.ls` - List event buses
- `eb.bus.create` - Create new event bus
- `eb.bus.rm` - Delete event bus with confirmation
- `eb.bus.policy.get` - Get event bus resource policy
- `eb.bus.policy.put` - Attach resource policy to event bus
- `eb.bus.policy.rm` - Remove policy statement from event bus
- `eb.rule.ls` - List EventBridge rules on a bus
- `eb.rule.new` - Create new EventBridge rule (event pattern or schedule)
- `eb.rule.set` - Update rule properties (state, description, pattern, schedule)
- `eb.rule.enable` / `eb.rule.disable` - Enable/disable rules
- `eb.rule.rm` - Delete rule and its targets
- `eb.target.ls` - List targets for a rule
- `eb.target.add` - Add target to rule with input transformation
- `eb.target.rm` - Remove targets from rule
- `eb.event.put` - Send test event to EventBridge
- `eb.pattern.test` - Test event pattern matching
- `eb.archive.ls` - List EventBridge archives
- `eb.archive.create` - Create event archive for replay
- `eb.replay.ls` - List replays
- `eb.replay.start` - Start event replay from archive
- `eb.replay.cancel` - Cancel running replay
- `eb.pipes.ls` - List EventBridge Pipes
- `eb.pipes.create` - Create new pipe (source to target)
- `eb.pipes.start` / `eb.pipes.stop` - Start/stop pipes
- `eb.pipes.rm` - Delete pipe
- `sch.ls` - List EventBridge Scheduler schedules
- `sch.create` - Create new schedule
- `sch.rm` - Delete schedule
- `sch.run` - Create one-shot schedule for immediate execution

### Secrets Manager

- `sm.ui` - Interactive Secrets Manager UI with fuzzy menus
- `sm.set` - Create or update secret with file/stdin/prompt input
- `sm.get` - Retrieve secret value with optional jq filtering
- `sm.get.many` - Batch retrieve multiple secrets
- `sm.ls` - List all secrets with names and ARNs
- `sm.describe` - Show detailed secret metadata
- `sm.rotate.enable` - Enable automatic rotation with Lambda function
- `sm.rotate.now` - Trigger immediate secret rotation
- `sm.replicate` - Replicate secret to multiple regions
- `sm.policy.validate` - Validate resource policy JSON
- `sm.policy.put` - Attach resource policy to secret
- `sm.policy.get` - Show current resource policy
- `sm.tag` / `sm.untag` - Add/remove tags from secrets
- `sm.rm` - Soft delete secret with recovery window
- `sm.rm.now` - Force delete secret without recovery
- `sm.restore` - Restore deleted secret
- `sm.help` - Show comprehensive help and examples

### Organizations & IAM

- `orgmap` - Interactive AWS Organizations mapper with OU/account tree, SCPs, regions, and IAM aliases
- `crosscheck` - Scan IAM for risky trust policies and overly broad permissions
- `iamwho` - Show detailed current AWS identity, policies, and permissions

### Cost Management

- `cost` - Interactive AWS Cost Explorer with fuzzy filters, grouping, and drill-down
- `cost.quick` - Quick cost view (last 3 months, monthly, by service)

## Hardware & USB

- `flash` - ISO to USB flasher with picker, progress, and strong verification using dd with hash checking
- `usb` - Interactive USB menu with all operations
- `usbinfo` - List USB devices with lsusb output
- `usbls` - Show USB partitions and mountpoints for selected device
- `usbmount` - Mount USB partition to /mnt/usb-\* directory
- `usbumount` - Unmount and power off USB device safely
- `usbformat` - Format USB device with filesystem choice (fat32/exfat/ntfs/ext4)
- `usbburn` - Quick write ISO to USB device with progress
- `usbclone` - Create or restore USB device images bidirectionally
- `usbwipe` - Securely wipe USB device with dd and zero fill
- `usbperf` - USB write speed test with dd benchmark
- `usb_peek` - Browse USB contents with FZF preview and file operations

## SSH & Remote Access

- `sshgen` - Generate ed25519 SSH keypair with clipboard copy
- `sshsave` - Send public key to remote server via SSH
- `sshlist` - Fuzzy pick host from ~/.ssh/config and connect
- `sshconf` - Create new Host entry in ~/.ssh/config interactively
- `sshclean` - Fuzzy remove broken known_hosts entries
- `mykeys` - Display all SSH public keys

## Docker & Containers

- `dupdate` - Pull updates and roll the current compose stack
- `dinto` - Jump into running Docker container with bash/sh fallback
- `dlogs` - Follow logs on multiple containers with multi-select
- `dtop` - Show top processes inside selected container
- `dcp` - Copy files out of a container to local directory
- `dnet` - Quick Docker network overview showing containers per network
- `dimgls` - List Docker images by size and optionally delete picked ones
- `dvolrm` - Pick dangling volumes interactively and remove
- `drestart` - Restart chosen container cleanly
- `ddeepclean` - Prune everything older than 24h including images, containers, volumes
- `dprune` - Complete Docker cleanup combining all termination functions
- `dgo` / `dsh` - Fuzzy jump into container or image with interactive controls
- `tercon` - Terminate all containers forcefully
- `tervol` - Remove all Docker volumes
- `terimg` - Remove all Docker images
-

## Git & Development

### Git Operations

- `gck` - Interactive git checkout with branch picker showing recent branches and commit previews
- `ggrep` - Search git commits with interactive preview, searches commit messages and diffs
- `gll` - Show last commit details with full diff
- `gllc` - Show last commit diff stats only
- `bll` - Show full branch diff vs base with pager
- `bllc` - Show branch diff stats vs base
- `gitwho` - Show top repo contributors with commit counts
- `bws` - Open current git repo on GitHub in browser
- `prs` - Open GitHub pull requests page for current repo
- `prr` - Open specific PR for current branch
- `issues` - Open GitHub issues page for current repo
- `dlb` - Delete all local git branches except current one (DANGEROUS)
- `groot` - Go to git repository root directory
- `ghkey` - Generate GitHub SSH key, add to agent, copy public key to clipboard, update SSH config

### Pull Request Management

- `mpr` - Comprehensive GitHub PR helper with create/open/view/ready commands
- `mpr create` - Create PR with auto-detection of base branch and upstream handling
- `mpr open` - Open PR in browser
- `mpr view` - Show PR details in terminal
- `mpr ready` - Mark draft PR ready for review

## System & Storage

### Disk Management

- `diskusage` - Interactive disk usage analysis using dua-cli
- `storage` - Interactive storage analysis using ncdu with system directory exclusions
- `diskspace` - Show disk space usage for home directory with human-readable format
- `suspend` - System suspend via systemctl or pm-suspend
- `hibernate` - System hibernate via systemctl or pm-hibernate

### System Monitoring

- `heat` - CPU temperature with optional GPU/FAN info, multiple output formats
- `hz` - Show current display refresh rate using xrandr/hyprctl/modetest
- `pspick` - Pick process with FZF from ps output sorted by memory usage
- `pstreef` - Show process tree for selected process using pstree
- `pstop` - Kill selected process with sudo kill -9
- `psf` - Find and kill processes with FZF picker, supports custom signals

## Files & Clipboard

### File Operations

- `extract` - Smart archive extractor with fuzzy matching, supports tar.gz/tar.bz2/zip/rar/7z/deb and more
- `shatter` - Secure file deletion with 69-pass shred, supports FZF selection or direct file arguments
- `rmw` - FZF delete picker with preview using fd/find
- `vv` - Open file with nvim using FZF picker
- `mdd` - Create directory and cd into it
- `files` - Open file manager (nautilus)

### Clipboard & Data Transfer

- `clipdir` - Advanced directory ⇄ clipboard with tar compression, progress, and size limits
- `cpd` - Copy directory contents to clipboard with interactive ignore patterns
- `cpf` - Copy picked files to clipboard with size limits
- `copy` - Copy stdin to clipboard with cross-platform support (wl-copy/xclip/OSC52)
- `paste` - Paste from clipboard to stdout
- `ccmd` - Copy command output to clipboard
- `cop` - Copy terminal output to clipboard, tmux/kitty aware with fallback to command history

## Desktop & UI

### Theme & Appearance

- `apply_gnome` - Apply custom GNOME theme, icons, and fonts via gsettings
- `wallpaper` - Comprehensive wallpaper manager for desktop and login (swww + waypaper)
- `kittytheme` - Set kitty terminal theme from config directory
- `themes`  Switches my themes across Hyprland, Starship, tmux, wallpaper, and dircolors in one command.

### Input & Display

- `kb` - Set keyboard layout across Wayland/X11/TTY with persistence via localectl
- `br_set` - Set brightness to specific percentage, works with brightnessctl/light/xbacklight/ddcutil/sysfs
- `br_up` - Increase brightness by specified step (default 5%)
- `br_down` - Decrease brightness by specified step (default 5%)
- `br_info` - Show current brightness percentage with visual bar using multiple backends
- `bth` - Bluetooth helper to connect/disconnect devices from terminal with interactive device selection

## Audio & Media

- `w` - Whisper.cpp voice transcription with clipboard copy, supports PipeWire/ALSA recording (I usually use ALT + W though)
- `animations` - FZF picker for available terminal animations.
- `clock` - Display terminal clock using tty-clock

## Web & Apps

- `app` - Open websites as native Chrome app windows using "Default" profile, supports FZF picker or direct URL/alias

## Notifications & Reminders

- `notify` - Schedule notifications with FZF time picker, supports systemd-run or background processes
- `reminder` - Remote API-based reminder system with unit picker and scheduling
- `remindme` - Simple local reminder that sleeps then shows message

## Sync & Backup

- `sync` - Comprehensive package sync for APT, snap, flatpak, pip, npm, cargo, rustup, go, nix, brew, and GNOME keybindings
- `syncgnome` - Full GNOME settings and extensions backup/restore system

## Development Tools

### Environment Management

- `le` - Fuzzy .env file loader with safe parsing and trust modes
- `loc` - Count lines of code excluding node_modules/dist/build directories using cloc

### Terminal & Shell

- `txkill` - Kill all tmux sessions
- `please` - Rerun last command with sudo prefix
- `man` - Enhanced man pages with colored output using LESS_TERMCAP
- `precmd` - ZSH hook for terminal title and newline before prompt
- `clr` - Print ANSI color codes for terminal formatting

## Utilities

- Various helper functions for colors, error handling, system detection and a whole lotta gang shit.

