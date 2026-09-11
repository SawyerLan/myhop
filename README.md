# myhop

English | [简体中文](README.zh-CN.md)

Jump straight into any MySQL database — including the ones your laptop can't
reach directly and only a bastion host can — by picking it from an `fzf`
list. No password prompt, no remembering which jump host goes with which
instance.

Two things make this different from just aliasing `mysql -h ...` commands:

- **Bastion-aware.** Most managed databases aren't reachable directly from
  your laptop — you have to hop through a bastion host first. `myhop` treats
  "connect via bastion X" and "connect directly" as first-class, equally easy
  options, per instance.
- **No plaintext passwords, anywhere.** Not in `myhop`'s own config file, not
  on your laptop, not on the bastion. See [Security model](#security-model).

Works with MySQL and anything that speaks its wire protocol — TiDB, MariaDB,
cloud-managed instances like Tencent CDB, etc.

```
$ myhop
  local-dev    -         local_dev    127.0.0.1    3306   root    -
> user-test    mon-pro   user_test    10.0.2.8     3306   app     user_db
  order-prod   mon-pro   order_prod   10.0.1.5     3306   app     order_db
  alias        bastion   login-path   host         port   user    database
  3/3
Select a MySQL instance >
```

## Why

If you manage more than a couple of databases, you've probably got a
`~/.ssh/config` full of bastion hosts and a sticky note somewhere with
passwords. `myhop` doesn't reinvent database connections — it's a thin layer
on top of two things that already do the hard part correctly:

- **`mysql_config_editor`** (ships with the official MySQL client) stores
  credentials in an obfuscated `~/.mylogin.cnf`, so nothing sensitive lives in
  `myhop`'s own config file.
- **`mycli`** (or plain `mysql` as a fallback) does the actual connecting,
  with `--login-path` handling authentication.

`myhop` just remembers the alias → bastion → login-path mapping and gives you
an `fzf` picker instead of memorizing hostnames.

## Requirements

- `bash`, `ssh`
- [`fzf`](https://github.com/junegunn/fzf) — the picker
- `mysql_config_editor` — from the official MySQL client package. **Not**
  included with MariaDB's client. See [Requirements notes](#requirements-notes)
  below if your distro only ships MariaDB.
- [`mycli`](https://www.mycli.net/) — optional but recommended (syntax
  highlighting, autocompletion). Falls back to plain `mysql` if absent.

The `install.sh` script below tries to install all of these for you.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/SawyerLan/myhop/main/install.sh | bash
```

This installs `myhop` to `~/.local/bin`, a bash completion script, and
attempts to install `fzf`, `mysql_config_editor`, and `mycli` via your system
package manager. Options (append after `| bash -s --`, e.g.
`... | bash -s -- --system`):

```bash
--system      # install to /usr/local/bin instead
--skip-deps   # only install the myhop script, skip dependencies
```

Prefer not to pipe a script into `bash` from a URL? Clone the repo and read
`install.sh` yourself first — it does the exact same thing:

```bash
git clone https://github.com/SawyerLan/myhop.git
cd myhop
./install.sh
```

Uninstall by deleting `~/.local/bin/myhop` and
`~/.local/share/bash-completion/completions/myhop` (or the `/usr/local/bin`
equivalents if you used `--system`).

### Requirements notes

RHEL/CentOS 7 and similar distros default to MariaDB's client, which does not
include `mysql_config_editor`. `install.sh` will tell you if this happens.
`scripts/extract-mysql-config-editor.sh` pulls just that one binary out of the
official MySQL client RPM (it has no dependency on `libmysqlclient`, so it
coexists with an existing MariaDB install without conflicts):

```bash
./scripts/extract-mysql-config-editor.sh        # defaults to el7/x86_64
./scripts/extract-mysql-config-editor.sh 8 x86_64
```

## Usage

```bash
myhop                  # fzf-pick an instance and connect
myhop connect <alias>  # connect directly, skipping the picker
myhop add               # register a new instance (interactive)
myhop list              # show all instances (host/port/user/database)
myhop test <alias>       # probe connectivity for one instance
myhop test --all         # probe connectivity for every instance
myhop edit <alias>       # change host/port/user/password/bastion/database
myhop rm <alias>         # remove an instance and its stored credential
```

### Adding an instance

```
$ myhop add
Alias (shown in myhop, e.g. order-prod): order-prod
Bastion (Host alias from ~/.ssh/config; leave empty for a direct connection): mon-pro
login-path name (credential name, default: same as alias):
Database host: 10.0.1.5
Port (default 3306):
Database user (default root): app
Default database (optional, press enter to skip): order_db
mycli path override on that machine (optional, press enter for default 'mycli'):

Running mysql_config_editor — enter the database password when prompted (input is hidden):
Enter password:
Verifying connection...
OK: connection verified
Saved to ~/.config/myhop/instances.tsv
```

Two connection modes are supported:

- **Via a bastion** — set "Bastion" to a `Host` entry from your
  `~/.ssh/config`. `myhop` runs `ssh -t <bastion> ...` and the credential is
  stored on the bastion, not on your laptop.
- **Direct** — leave "Bastion" empty (stored internally as `-`). `myhop` runs
  the SQL client locally; the credential is stored in your own
  `~/.mylogin.cnf`.

### Config file

`~/.config/myhop/instances.tsv` (override the path with `$MYHOP_CONFIG`), one
instance per tab-separated line:

```
alias  bastion  login-path  database  mycli_bin
```

- `bastion`: an SSH config `Host` alias, or `-` for a direct connection
- `login-path`: the name used with `mysql_config_editor` / `mycli
  --login-path`
- `database`: optional default database
- `mycli_bin`: optional override for how to invoke mycli on that machine
  (only needed if it's not the default `mycli` on `PATH` there — e.g. behind
  a pyenv shim that only exists under a non-default Python version)

None of these fields are secret — the actual host/port/user/password live
encrypted in `~/.mylogin.cnf` on whichever machine opens the connection, never
in this file.

## Security model

`mysql_config_editor` obfuscates credentials with a fixed, reversible scheme
— it is **not** strong encryption. Its real security boundary is standard
file permissions (`~/.mylogin.cnf` is `600`) plus whoever can log into that
machine. This is the same trust model as `~/.pgpass`, ssh-agent, or most
"convenience" credential stores: fine for engineers who already have shell
access to the box, not a substitute for a secrets manager in a
multi-tenant or zero-trust environment.

## Bash completion

`install.sh` installs `completions/myhop.bash` for you. If your shell doesn't
autoload from `~/.local/share/bash-completion/completions`, source it
manually from your `~/.bashrc`:

```bash
source ~/.local/share/bash-completion/completions/myhop
```

## License

MIT
