# KaliForge

Kali Rolling cloud workspace for authorized labs and CTFs. Combines the Kali Railway reference with RailDK's SSH, 9router, and split GitHub backups. Existing reference repositories remain untouched.

## Persistence

Railway volume mounted at `/root` is primary persistence across restarts/redeploys. Two private GitHub repositories provide a separate off-volume backup:

- `APPS_REPO=owner/repo`: `/root/.9router`. SQLite databases use `.backup`; transient files, logs, `.env`, and API-key secrets are excluded. Files not matched by these exclusions can still contain secrets.
- `KALI_REPO=owner/repo`: allowlisted `/root/tools`, `/root/wordlists`, `/root/labs`, and `.zshrc`, `.bashrc`, `.vimrc`, `.tmux.conf`. `.env`, `*.key`, and `*.pem` excluded. Does not back up the OS or apt-installed packages; Dockerfile rebuilds those.

Both repos must already exist and be private. Set `GITHUB_TOKEN` with contents read/write access. Restore runs before services; backups run every `SYNC_INTERVAL` seconds (default 300). Manual: `app-sync backup`, `kali-sync backup`; status: `app-sync status`, `kali-sync status`.

## Services

- `22/tcp`: SSH (Railway TCP proxy)
- `PORT/http`: ttyd browser terminal (Railway-provided `PORT`)
- `20128/http`: 9Router; do not publish publicly until management routes are independently authenticated. Its API key mechanism does not establish that the admin UI is protected.

Railway needs explicit public TCP proxy/domain routing for non-HTTP ports. Keep 9Router private; public dashboard/admin exposure is not verified safe.

`ROOT_PASSWORD` is required; startup fails closed if missing. It protects ttyd, SSH password login, and the 9Router dashboard via its `INITIAL_PASSWORD` setting. Existing 9Router password hashes take precedence over `INITIAL_PASSWORD`; if you already initialized a different 9Router password, change it in 9Router settings or use its existing password. Set `AUTHORIZED_KEYS` too, then prefer disabling SSH password login once key access is verified. Do not expose unauthenticated services. SSH password authentication remains enabled even when `AUTHORIZED_KEYS` is set; use a strong `ROOT_PASSWORD`. Consider Railway resource limits: Kali + Metasploit + Node may exceed small memory allocations. Attach a Railway volume at `/root` in the service settings; the config files do not create a volume.

## Variables

Required/optional: `ROOT_PASSWORD`, `AUTHORIZED_KEYS`, `GITHUB_TOKEN`, `APPS_REPO`, `KALI_REPO`, `SYNC_INTERVAL`, `USERNAME`, `PORT`. Attach the `/root` volume manually in Railway service settings.

## Build

```sh
docker build -t kaliforge .
```

## Security / scope

Use Kali tools only against systems you own or have explicit authorization to test. GitHub backup is an allowlisted workspace backup, not a full Kali image or package persistence. Inspect secrets before committing app state; keep credentials in Railway Variables, not Git or backup repositories.

ponytail: apt-installed packages persist across container restarts, not image rebuilds; add required package names to the Dockerfile package list when you need them after redeploy.
