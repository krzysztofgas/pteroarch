# 🦖 PteroArch

**Set up your own game server panel on Arch Linux by answering a few questions.**

PteroArch is a friendly, step-by-step installer for [Pterodactyl](https://pterodactyl.io), a free, open-source panel for running game servers (Minecraft, Rust, Valheim and many more) in Docker containers. Pterodactyl's official guides are written for Ubuntu and Debian. PteroArch does the Arch-specific work for you.

```
   PteroArch  Pterodactyl for Arch Linux  · Step 2 of 6
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━────────────────────────────────────────

  ❯ How will people reach the panel?

  ╭─ Help ─────────────────────────────────────────────────────────────────╮
  │ A domain is a name like panel.example.com that points to your          │
  │ server's IP address. You create it at your domain provider with an 'A  │
  │ record'. No domain? Pick 2 - it works fine for testing at home.        │
  ╰────────────────────────────────────────────────────────────────────────╯
  ❯ 1  I have a domain name pointing at this server
    2  Use the IP address only
       No HTTPS - fine for testing on a home network.
  ↑↓ move · Enter select · ? help · Esc back
```

_(In your terminal it's in color, with a spinning progress display while it installs.)_

---

## ✨ What it does

- 🧭 **Guides you through setup.** One question at a time, with sensible defaults. Press Enter to accept them.
- ⌨️ **Works with the arrow keys.** Move through menus with the arrows (or `W`/`S`), confirm with Enter, and press Esc to go back.
- 🙋 **Helps when you're unsure.** Press `?` at any question marked `(?)` for a plain-language explanation.
- 👀 **Lets you review everything first.** Nothing changes until you confirm on the review screen, and you can go back and edit any section.
- 🎨 **Easy to follow.** Colors, a progress bar, live spinners and time estimates show what's happening and how long it usually takes.
- 🖥️ **Looks right everywhere.** It adapts to your terminal: full symbols on a desktop terminal, simpler ones on the bare Linux console, plain ASCII on serial lines.
- 🔏 **Checks what it downloads.** The panel, Wings and Composer downloads are verified against their published SHA-256 checksums.
- 🔁 **Lets you recover from errors.** If a step fails, you see why and get a tip for fixing it, then you can try again, skip, or stop.
- 💾 **Resumes where it stopped.** Run it again after quitting or rebooting and it continues from the last finished step.
- 🔒 **Sets up HTTPS for you.** It gets free Let's Encrypt certificates and renews them automatically.
- 🧱 **Can configure a firewall.** It sets up ufw (or adds rules to firewalld) and keeps your SSH port open.
- 🐧 **Follows Arch conventions.** It uses `php-legacy` (PHP 8.3, the version Pterodactyl is tested on), `valkey` for Redis, the `http` web user, and systemd timers instead of cron.

## 🧩 Three ways to install

| Option                           | Good for                                                                |
| -------------------------------- | ----------------------------------------------------------------------- |
| **Panel + Wings on one machine** | A single server that hosts the panel and the games. The easiest choice. |
| **Panel only**                   | Running the website here and the games on other machines.               |
| **Wings only**                   | Adding this machine as a game node to a panel you already have.         |

_Panel_ is the website you log into. _Wings_ is the agent that runs the game servers.

## 📋 Before you start

- A machine running **Arch Linux** (x86_64 or ARM64) with root access
- **2 GB RAM** or more is recommended, plus whatever your game servers need
- A **domain name** pointing to the server (e.g. `panel.example.com`), if you want HTTPS
- **Ports 80 and 443** reachable from the internet, for HTTPS certificates

> 💡 Using Cloudflare? Set the DNS record to **DNS only** (grey cloud). Wings and Let's Encrypt need a direct connection.

## 🚀 Quick start

1. Copy `installer.sh` to your server, for example:
   ```bash
   scp installer.sh root@your-server:/root/
   ```
2. Run it as root:
   ```bash
   sudo bash installer.sh
   ```
3. Answer the questions, check the review screen, and press **Enter** to install.

While you answer:

- In menus, move with the **arrow keys** (or `W`/`S`, `J`/`K`, or a number) and press **Enter** to select.
- For yes/no questions, switch with **←/→** (or `A`/`D`, `Y`/`N`) and press **Enter**.
- Press **Enter** to accept the suggestion shown in `[brackets]`.
- Press **`?`** for help on any question marked `(?)`.
- Press **Esc** to go back: first to the start of the current step, then to the previous step. What you already typed is kept as the suggestion.
- Type a city for the timezone, like `warsaw` or `new york`. PteroArch finds the full name for you.
- Leave the password empty to get a strong one generated for you.
- Press **Ctrl+C** any time to stop. Nothing changes before the review screen, and an interrupted install can be resumed.

That's it ☕ An install usually takes 5–15 minutes. At the end you get your login details. They're also saved (readable by root only) in `/root/pterodactyl-credentials.txt`.

## 🛠️ Options

```bash
sudo bash installer.sh --dry-run    # answer the questions and see the plan, without installing anything
sudo bash installer.sh --verbose    # show the full command output instead of a spinner
sudo bash installer.sh --no-color   # plain text without colors (NO_COLOR=1 works too)
sudo bash installer.sh --no-anim    # no spinners or animations
sudo bash installer.sh --no-keys    # no arrow-key menus: type a number and press Enter instead
sudo bash installer.sh --ascii      # plain ASCII symbols only
sudo bash installer.sh --symbols=basic   # auto (default), rich, basic or ascii
sudo bash installer.sh --version
sudo bash installer.sh --help
```

Colors, animations and arrow-key menus switch off on their own when they can't work, for example when the output is redirected to a file or the answers are piped in. Without arrow-key menus you type a number and press Enter, and `<` goes back.

**Seeing empty boxes or question marks instead of symbols?** PteroArch picks a symbol set that fits your terminal: `rich` for desktop terminals, `basic` (only line-drawing characters) for the Linux console, and `ascii` for serial consoles and non-UTF-8 locales. If the guess is wrong, for example on a machine with very few fonts installed, press **S** on the welcome screen to switch, or start with `--ascii`.

To install a specific panel release instead of the newest 1.x:

```bash
sudo PANEL_VERSION=v1.15.2 bash installer.sh
```

## 🎮 After installing

1. Open your panel URL and log in.
2. Go to **Admin → Nodes**. A green heart ❤️ means Wings is connected.
3. Go to **Admin → Servers → Create New**, pick a game (an _egg_), and start playing.

Adding more game machines later? Run PteroArch on each one and choose **Wings only**. When it asks, paste the auto-deploy command from your node's **Configuration** tab in the panel.

## 🩺 If something goes wrong

PteroArch shows the last lines of output in a red box, along with a "What usually helps" tip for that step. Then you can choose:

- **Try again**: fix the problem (a second terminal is handy) and retry
- **Skip**: continue without that step
- **Show the full output**: read everything that step printed
- **Stop for now**: quit and run the script again later to resume

At the end, a health check shows which services are running. You'll see **All done!** only when everything checks out.

Common fixes:

| Problem                                          | Try this                                                         |
| ------------------------------------------------ | ---------------------------------------------------------------- |
| Package download fails                           | Refresh your mirrors (`reflector` or `/etc/pacman.d/mirrorlist`) |
| Let's Encrypt fails                              | Check that your domain points here and port 80 is open           |
| Docker or firewall fails right after the upgrade | Reboot (a new kernel was installed), then run PteroArch again    |
| Wings won't start                                | `journalctl -u wings -n 50`                                      |
| Symbols show as boxes or `?`                     | Press **S** on the welcome screen, or run with `--ascii`         |
| Arrow keys don't work in your terminal           | Run with `--no-keys` and type the numbers                        |

The full log is in `/var/log/pteroarch.log`.

## 📁 Where things live

| What                            | Where                                         |
| ------------------------------- | --------------------------------------------- |
| Panel files                     | `/var/www/pterodactyl`                        |
| Panel settings & encryption key | `/var/www/pterodactyl/.env` (💾 back this up) |
| Wings config                    | `/etc/pterodactyl/config.yml`                 |
| Game server files               | `/var/lib/pterodactyl/volumes`                |
| Login details                   | `/root/pterodactyl-credentials.txt`           |
| Installer progress              | `/root/.pteroarch`                            |

Services: `nginx`, `php-fpm-legacy`, `mariadb`, `valkey`, `pteroq`, `ptero-schedule.timer`, `docker`, `wings`.

## ⚠️ Good to know

- PteroArch starts with a full system upgrade (`pacman -Syu`), because Arch doesn't support partial upgrades. It refreshes `archlinux-keyring` first, so machines that haven't been updated in a while don't fail on signature errors.
- If you skip a failed step, your answers are kept. Run PteroArch again and choose **Continue** to retry it.
- It installs **Pterodactyl 1.x**, the stable line. Pterodactyl 2.0 is still in beta.
- On a rolling-release system, a big PHP update can surprise you. If you chose Arch's main `php` package, consider pinning it.
- Docker publishes game ports directly, so those ports are reachable even if your firewall would otherwise block them.
- Running the panel and public game servers on one machine is convenient. For hosting other people's servers, keep the panel on a separate machine.

---

PteroArch is a community script and isn't affiliated with the Pterodactyl project. Pterodactyl is licensed under the MIT license by its authors. Have fun and happy hosting! 🎉
