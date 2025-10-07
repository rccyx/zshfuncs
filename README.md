# zshfuncs

A terminal-first productivity toolkit with 200+ functions for sys ad, cloud ops, dev worfklows, and daily automations that I use.

## Funcs

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
- `tercon` - Terminate all containers forcefully
- `tervol` - Remove all Docker volumes
- `terimg` - Remove all Docker images

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

- `s3up` - Upload files/folders to S3 with multipart resume support and progress
- `s3down` - Download from S3 with resume support for large files
- `s3ls` - List S3 objects with FZF search and metadata preview
- `s3rm` - Delete S3 objects with confirmation, supports batch operations
- `s3buckets` - List available S3 buckets
- `s3who` - Show current AWS caller identity

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
- `loadpg` - Restart GPG agent and set TTY environment

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
- `flash` - ISO to USB flasher with device picker, progress, and SHA256 verification

- `wifi` - Interactive WiFi connection with network scanner and password prompt
- `wifireconnect` - Reconnect to selected saved network
- `wifipass` - Show password for current WiFi network and copy to clipboard
- `wifiresume` - Turn on WiFi radio
- `wifikill` - Turn off WiFi radio
- `wifiqr` - Generate QR code for current WiFi network connection
- `connected-devices` - Scan for devices on local network using arp-scan
- `netspeed` - Test internet speed using speedtest-cli with clipboard copy

- `sshgen` - Generate ed25519 SSH keypair with clipboard copy
- `sshsave` - Send public key to remote server via SSH
- `sshlist` - Fuzzy pick host from ~/.ssh/config and connect
- `sshconf` - Create new Host entry in ~/.ssh/config interactively
- `sshclean` - Fuzzy remove broken known_hosts entries
- `mykeys` - Display all SSH public keys

- `gck` - Interactive git checkout with branch picker showing recent branches and commit previews
- `ggrep` - Search git commits with interactive preview, searches commit messages and diffs
- `gll` - Show last commit details with full diff
- `gllc` - Show last commit diff stats only
- `gitwho` - Show top repo contributors with commit counts
- `bws` - Open current git repo on GitHub in browser
- `prs` - Open GitHub pull requests page for current repo
- `issues` - Open GitHub issues page for current repo
- `dlb` - Delete all local git branches except current one (DANGEROUS)
- `groot` - Go to git repository root directory
- `ghkey` - Generate GitHub SSH key, add to agent, copy public key to clipboard, update SSH config

- `diskusage` - Interactive disk usage analysis using dua-cli
- `storage` - Interactive storage analysis using ncdu with system directory exclusions
- `diskspace` - Show disk space usage for home directory with human-readable format

- `clipdir` - Copy or paste current directory as tar stream
- `cpd` - Copy directory contents to clipboard with interactive ignore patterns
- `cpf` - Copy picked files to clipboard with size limits
- `copy` - Copy stdin to clipboard with cross-platform support (wl-copy/xclip/OSC52)
- `paste` - Paste from clipboard to stdout
- `ccmd` - Copy command output to clipboard
- `extract` - Smart archive extractor with fuzzy matching, supports tar.gz/tar.bz2/zip/rar/7z/deb and more
- `shatter` - Secure file deletion with 69-pass shred, supports FZF selection or direct file arguments
- `rmw` - FZF delete picker with preview using fd/find
- `vv` - Open file with nvim using FZF picker
- `mdd` - Create directory and cd into it
- `files` - Open file manager (nautilus)
- `cop` - Copy terminal output to clipboard, tmux/kitty aware with fallback to command history

- `apply_gnome` - Apply custom GNOME theme, icons, and fonts via gsettings
- `wallpaper` - Wayland wallpaper manager using swww backend with waypaper UI
- `kb` - Set keyboard layout across Wayland/X11/TTY with persistence via localectl
- `kittytheme` - Set kitty terminal theme from config directory
- `hz` - Show current display refresh rate using xrandr/hyprctl/modetest
- `br_set` - Set brightness to specific percentage, works with brightnessctl/light/xbacklight/ddcutil/sysfs
- `br_up` - Increase brightness by specified step (default 5%)
- `br_down` - Decrease brightness by specified step (default 5%)
- `br_info` - Show current brightness percentage with visual bar using multiple backends

- `w` - Whisper.cpp voice transcription with clipboard copy, supports PipeWire/ALSA recording
- `app` - Open websites as native Chrome app windows using "Default" profile, supports FZF picker or direct URL/alias
- `bth` - Bluetooth helper to connect/disconnect devices from terminal with interactive device selection
- `sound-animate` - Audio visualizer using cava
- `animations` - FZF picker for available terminal animations

- `pspick` - Pick process with FZF from ps output sorted by memory usage
- `pstreef` - Show process tree for selected process using pstree
- `pstop` - Kill selected process with sudo kill -9
- `psf` - Find and kill processes with FZF picker, supports custom signals
- `txkill` - Kill all tmux sessions

- `notify` - Schedule notifications with FZF time picker, supports systemd-run or background processes
- `remindme` - Simple reminder that sleeps then shows message
- `tfa` - Generate TOTP codes via oathtool, secret entered interactively or as parameter, copies to clipboard
- `please` - Rerun last command with sudo prefix
- `genpass_easy` - Generate hex password (16 bytes as 32 hex chars)
- `genpass_mid` - Generate base64 alphanumeric password (32 chars)
- `genpass_hard` - Generate complex password with special characters (32 chars)
- `man` - Enhanced man pages with colored output using LESS_TERMCAP
- `precmd` - ZSH hook for terminal title and newline before prompt
- `loc` - Count lines of code excluding node_modules/dist/build directories using cloc
- `clr` - Print ANSI color codes for terminal formatting
- `clock` - Display terminal clock using tty-clock

And more...

