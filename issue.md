# Security & Intrusion Awareness Toolkit

## Context

This machine is operated terminal-first by a high-signal user who installs software rapidly, pulls dependencies across ecosystems (npm, pip, cargo, nix, binaries), and avoids UI-heavy security tooling.

The goal is **early detection, visibility, and containment**, not antivirus theater.

We assume:

- Linux workstation
- SSH-heavy workflows
- Frequent dev tooling installs
- Preference for read-only, fast, non-daemon tools
- Zero tolerance for noisy or low-signal output

This toolkit focuses on **attack-surface awareness**, **persistence detection**, and **post-compromise visibility**.

## Threat Model (What We Care About)

We are NOT optimizing for:

- Email malware
- Script-kiddie ransomware
- Signature-based viruses

We ARE optimizing for:

- Supply-chain compromise
- Silent persistence mechanisms
- Credential and token exfiltration
- Low-noise crypto miners or loaders
- Unauthorized outbound network activity
- Config and auth drift

## Required Tools

### 1. `persist` — Persistence Detector

**Purpose**  
Detect anything that tries to make itself survive reboots or logouts.

**What it checks**

- systemd system services
- systemd user services
- cron jobs and anacron
- systemd timers
- `~/.ssh/authorized_keys`
- shell RC files (`.zshrc`, `.bashrc`, `.profile`)
- new executables in writable PATH directories

**What it outputs**

- New or modified persistence entries
- Clear diff-style signal (what changed, where)

**What it must NOT do**

- No remediation
- No auto-deletion
- No daemon

---

### 2. `netwatch` — Network Egress Visibility

**Purpose**  
Answer: “Who is my machine talking to right now?”

**What it checks**

- Active outbound TCP/UDP connections
- Long-lived connections
- Destination IP, ASN, and country (best-effort)
- Process → connection mapping
- DNS queries in-flight or recent

**What it outputs**

- Sorted, human-readable list of outbound activity
- Emphasis on unexpected or persistent connections

**What it must NOT do**

- No firewall rule changes
- No blocking by default
- No packet capture unless explicitly requested

---

### 3. `fence` — File Integrity & Drift Detector

**Purpose**  
Detect unauthorized or accidental changes to critical system files.

**Scope (intentionally limited)**

- `/etc`
- PAM configuration
- systemd unit directories
- `~/.ssh`
- sudoers
- user dotfiles (tracked paths only)

**Core behavior**

- Seal known-good state (hashes + metadata)
- Compare current state against seal
- Show diffs on demand

**What it must NOT do**

- No full filesystem hashing
- No background monitoring
- No alerts unless invoked

---

### 4. `verify` — Install-Time Sanity Checker

**Purpose**  
Add friction to unsafe installs without blocking flow.

**What it does**

- Show binary origin and install path
- Display file size and hash
- Check for signatures when available
- Highlight installs from temp or cache directories

**What it does NOT do**

- No trust decisions
- No blocking installs
- No package manager replacement

This is awareness, not enforcement.

---

### 5. `anomaly` — Runtime Behavior Scanner

**Purpose**  
Detect things that look wrong _while the system is running_.

**What it checks**

- Processes executing from `/tmp`, `/dev/shm`, cache dirs
- Processes with no owning package
- Processes holding deleted executables
- CPU or I/O activity during idle hours
- Suspicious parent-child process trees

**What it outputs**

- Ranked list of anomalies with reasons
- No verdicts, just signal

---

### 6. `sshguard` — SSH Hygiene Validator

**Purpose**  
Ensure SSH access hasn’t quietly drifted into an unsafe state.

**What it checks**

- Password auth enabled/disabled
- Root login state
- Authorized keys inventory
- Unexpected key additions
- SSH agent exposure

**What it must NOT do**

- No config rewriting
- No key removal
- No service restarts

---

### 7. Kill Switches (Incident Response)

These are **manual, intentional** controls.

#### `panicnet`

- Drop all outbound traffic except SSH
- Immediate containment mode

#### `panicuser`

- Stop user-level services and timers
- Preserve system access

#### `panicdisk`

- Remount sensitive directories read-only
- Prevent further writes during investigation

No prompts. No questions. Muscle memory only.

---

## Optional: Reality Checks

### `restorecheck`

Randomly select a backed-up file and:

- Restore it
- Verify checksum
- Verify permissions

Purpose: validate that backups are **actually usable**.

---

## Explicit Non-Goals

- No antivirus daemons
- No realtime scanning
- No signature databases
- No UI dashboards
- No auto-remediation

All tools must be:

- Fast
- Read-only by default
- Explicitly invoked
- Low-noise
- Scriptable

## Philosophy

This toolkit assumes:

- Compromise is about _time_, not _if_
- Detection beats prevention
- Awareness beats fear
- Silence is more dangerous than alerts

The goal is to **see clearly**, **decide fast**, and **contain surgically**.
