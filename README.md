---

# 🧹 SGM VPS Soft Wipe Tool

A powerful, interactive VPS maintenance and cleanup utility designed to safely reset a Linux server environment by removing user data, stopping non-essential services, clearing caches, and restoring a clean operational state—without breaking core system functionality.

---

## ⚡ What is this?

**SGM VPS Soft Wipe Tool** is a root-level Linux administration script that performs a controlled system cleanup.

It is built for situations where you want to:

* Reset a VPS environment after testing or development
* Remove all user-level changes safely
* Clean system caches, logs, and temporary files
* Kill active user processes
* Restore a fresh operational state without reinstalling the OS

Unlike a full OS reinstall, this tool keeps:

* SSH access
* Networking stack
* Core system services

---

## 🔥 Features

🧠 Smart pre-check system (detects containers & unsafe environments)
⚠️ Interactive confirmation before destructive actions
🧹 Stops non-essential services safely
👤 Kills all user-level processes
📁 Wipes user directories and system caches
📜 Clears logs, cron jobs, and temporary files
💾 Flushes RAM cache and cycles swap memory
📊 Live system dashboard (CPU, RAM, disk, network, uptime)
🔒 Root-only execution protection
📝 Activity logging for audit tracking

---

## 🧪 How it works

The script performs a structured 6-stage cleanup process:

1. Stops non-essential services
2. Terminates user processes
3. Wipes user and system data directories
4. Clears cron jobs and scheduled tasks
5. Flushes memory cache and swap
6. Restarts essential logging services

Finally, it optionally reboots the system for a fully clean state.

---

## 📊 Live System Monitor

Includes a built-in real-time dashboard showing:

* CPU model & usage stats
* Memory usage
* Disk usage
* Network interfaces
* System load & uptime
* Swap status

---

## ⚙️ Usage

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ShahedPlayz/Wipe-Vps-Data/main/wipe.sh | tr -d '\r')
```

> ⚠️ Must be run as **root**.

---

## 🛡️ Safety Features

✔ Detects container environments (LXC, Docker, OpenVZ)
✔ Prevents accidental execution without root
✔ Pre-wipe confirmation prompt
✔ Logs all operations to `/var/log/sgm_softwipe.log`
✔ Protects critical system services

---

## 💡 Use Cases

* VPS reset after testing scripts
* Cleaning compromised or cluttered environments
* Dev/test environment refresh
* System recovery preparation
* Automation pipeline cleanup

---

## ⚠️ Warning

This tool **deletes user data and processes permanently**.

It does NOT:

* Reinstall the OS
* Format the disk
* Touch core system integrity

Use only on systems you fully control.

---
