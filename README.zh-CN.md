# myhop

[English](README.md) | 简体中文

一秒直连任何一个 MySQL 数据库——包括那些本机根本连不上、必须经堡垒机才能到达的实例——从 `fzf` 列表里选一个就行，不用输密码，也不用记哪个实例对应哪台跳板机。

跟直接写一堆 `mysql -h ...` 的 alias 相比，myhop 的核心不同点是两条：

- **原生支持堡垒机跳转。** 大多数托管数据库本机都连不上，必须先经跳板机才能到达。myhop 把"经堡垒机连接"和"本机直连"当作同等重要、同样简单的两种模式，按实例各自配置。
- **任何地方都不存明文密码。** myhop 自己的配置文件里没有，本机没有，堡垒机上也没有。详见[安全模型](#安全模型)。

除了 MySQL，凡是兼容它协议的数据库都能用——TiDB、MariaDB，腾讯云 CDB 这类云托管实例等等。

```
$ myhop
  local-dev    -         local_dev    127.0.0.1    3306   root    -
> user-test    mon-pro   user_test    10.0.2.8     3306   app     user_db
  order-prod   mon-pro   order_prod   10.0.1.5     3306   app     order_db
  alias        bastion   login-path   host         port   user    database
  3/3
Select a MySQL instance >
```

## 为什么做这个

如果你管理的数据库超过两三个，大概率已经有一份写满堡垒机的 `~/.ssh/config`，密码存在某个便签或者脑子里。myhop 不重新发明连接数据库这件事本身——它只是薄薄一层，架在两个已经把"密码存储"和"连接"这两件事做对了的工具之上：

- **`mysql_config_editor`**（官方 MySQL 客户端自带）把凭据混淆存进 `~/.mylogin.cnf`，敏感信息不会出现在 myhop 自己的配置文件里。
- **`mycli`**（没有的话退回原生 `mysql`）负责真正建立连接，用 `--login-path` 完成鉴权。

myhop 只负责记住"别名 → 堡垒机 → login-path"这层映射关系，再给你一个 `fzf` 选择器，省得你去记一堆主机名。

## 依赖要求

- `bash`、`ssh`
- [`fzf`](https://github.com/junegunn/fzf) —— 交互选择器
- `mysql_config_editor` —— 来自官方 MySQL 客户端包，**MariaDB 客户端不带这个工具**。如果你的发行版默认只有 MariaDB 客户端，看下面的[依赖说明](#依赖说明)。
- [`mycli`](https://www.mycli.net/) —— 可选但推荐（语法高亮、自动补全）。没装的话自动退回原生 `mysql`。

下面的 `install.sh` 会尝试帮你把这些都装好。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/SawyerLan/myhop/main/install.sh | bash
```

会把 `myhop` 装到 `~/.local/bin`，装好 bash 补全脚本，并尝试用你系统的包管理器装 `fzf`、`mysql_config_editor`、`mycli`。可选参数（跟在 `| bash -s --` 后面，比如 `... | bash -s -- --system`）：

```bash
--system      # 装到 /usr/local/bin
--skip-deps   # 只装 myhop 本体，跳过依赖安装
```

不想直接把网上的脚本 pipe 进 `bash` 执行？可以先克隆仓库自己看一遍 `install.sh` 再跑，效果完全一样：

```bash
git clone https://github.com/SawyerLan/myhop.git
cd myhop
./install.sh
```

卸载：删掉 `~/.local/bin/myhop` 和 `~/.local/share/bash-completion/completions/myhop`（如果用了 `--system`，对应删 `/usr/local/bin` 下的文件）。

### 依赖说明

RHEL/CentOS 7 及类似发行版默认用的是 MariaDB 客户端，不带 `mysql_config_editor`。遇到这种情况 `install.sh` 会提示你。`scripts/extract-mysql-config-editor.sh` 可以只从官方 MySQL 客户端 RPM 包里单独抽取这一个二进制（它不依赖 `libmysqlclient`，跟你机器上已有的 MariaDB 客户端不会冲突）：

```bash
./scripts/extract-mysql-config-editor.sh        # 默认 el7/x86_64
./scripts/extract-mysql-config-editor.sh 8 x86_64
```

## 用法

```bash
myhop                  # fzf 选择实例并连接
myhop connect <别名>    # 跳过选择器，直接按别名连接
myhop add               # 交互式注册一个新实例
myhop list              # 列出所有实例（host/port/user/database）
myhop test <别名>       # 测试单个实例的连通性
myhop test --all         # 测试所有实例的连通性
myhop edit <别名>       # 修改 host/port/user/密码/堡垒机/数据库
myhop rm <别名>         # 删除一个实例及其对应的凭据
```

### 新增一个实例

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

支持两种连接模式：

- **经堡垒机** —— "Bastion" 填你 `~/.ssh/config` 里的一个 `Host` 别名。myhop 会执行 `ssh -t <堡垒机> ...`，凭据存在堡垒机上，不落在你本机。
- **本机直连** —— "Bastion" 留空即可（内部存成 `-`）。myhop 会在本机直接跑 SQL 客户端，凭据存进你自己的 `~/.mylogin.cnf`。

### 配置文件

`~/.config/myhop/instances.tsv`（可以用环境变量 `$MYHOP_CONFIG` 覆盖路径），每行一个实例，Tab 分隔：

```
别名  堡垒机  login-path  数据库  mycli_bin
```

- `堡垒机`：`~/.ssh/config` 里的 Host 别名，或者 `-` 表示本机直连
- `login-path`：`mysql_config_editor` / `mycli --login-path` 用的凭据名
- `数据库`：可选的默认数据库
- `mycli_bin`：可选，覆盖那台机器上 mycli 的调用方式（只有当那台机器上默认 `PATH` 里的 `mycli` 不可用时才需要填，比如它藏在某个非默认版本的 pyenv 环境下）

这几个字段都不是敏感信息——真正的 host/port/user/password 加密存在实际发起连接那台机器（本机或堡垒机）的 `~/.mylogin.cnf` 里，从不落在这个配置文件中。

## 安全模型

`mysql_config_editor` 对凭据做的是一种固定的、可逆的混淆处理——**不是**强加密。它真正的安全边界是标准的文件权限（`~/.mylogin.cnf` 是 `600`）加上"谁能登录那台机器"。这跟 `~/.pgpass`、ssh-agent，或者大多数"图方便"型凭据存储方案的信任模型是一样的：对已经有权限登录这台机器的工程师来说没问题，但在多租户或零信任环境下，它不能替代专门的密钥管理系统。

## Bash 补全

`install.sh` 会帮你装好 `completions/myhop.bash`。如果你的 shell 不会自动加载 `~/.local/share/bash-completion/completions` 目录，在 `~/.bashrc` 里手动 source 一下：

```bash
source ~/.local/share/bash-completion/completions/myhop
```

## License

MIT
