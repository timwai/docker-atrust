# docker-atrust

无需宿主机图形桌面，在 Ubuntu Server（amd64）上通过 Docker 使用深信服 aTrust Linux 客户端。

**当前设计：所有需要持久化或外挂的内容，只映射一个宿主机目录 `./runtime:/opt/atrust`。** 不内置 aTrust 官方 DEB；新容器启动时从该目录安装。没有 SOCKS5/HTTP 正向代理，保留 VNC、可选 noVNC 和厂商网页登录回调。网络模式仍为 Docker Compose 默认 bridge，不共享宿主机网络。

> 本工程为非官方社区衍生项目，与深信服及相关运营商无隶属关系。使用企业 VPN 前请确认授权；不提供规避厂商认证、MFA 或终端安全控制的功能。请不要公开企业专属 DEB、配置、证书及登录数据。

## 来源与许可证

本项目基于 [docker-easyconnect/docker-easyconnect](https://github.com/docker-easyconnect/docker-easyconnect) 改造，最初导入的上游源码版本是 [`e8fc56a7c518d83b6817e16713f765e3c652e3bf`](https://github.com/docker-easyconnect/docker-easyconnect/commit/e8fc56a7c518d83b6817e16713f765e3c652e3bf)。致谢原作者 Hagb 及 docker-easyconnect 贡献者，保留 [LICENSE.txt](LICENSE.txt)（WTFPL v2）。本仓库的开源许可**不覆盖**深信服 aTrust 专有客户端、商标或其下载包；Debian、TigerVNC、noVNC 等仍适用各自许可证。

本项目将用到的上游辅助脚本和 C 源文件直接收录在当前仓库，镜像构建阶段不克隆其他 GitHub 仓库。Ubuntu 24.04 测试分支的构建仍需要 Ubuntu 基础镜像与 Ubuntu APT 仓库；明确使用 `--official` 时还需深信服官方 CDN。

## Ubuntu 24.04 精简运行镜像（测试分支）

此分支针对企业门户提供的 **aTrust 2.5.16.30 Ubuntu AMD64 DEB** 做适配；保留 Docker Bridge、`./runtime:/opt/atrust` 唯一目录映射、VNC 和容器首次启动安装客户端的架构，不提供 HTTP/SOCKS 正向代理。

- 两个构建阶段统一使用 `ubuntu:24.04`，所有系统包使用 Ubuntu 官方 APT 仓库（包括 universe），不再配置 Debian 11 历史快照。
- 删除系统 `libssl1.1`、`libldap-2.4-2`、重复的 Qt5 运行包，以及不用于运行的 `libssl-dev`，优先使用厂商 DEB 自带的库。
- 明确提供 Qt XCB 插件、GTK、X11 需要的底层系统动态库；系统依赖清单基于 129 个 ELF 的 `DT_NEEDED` 分析，但未覆盖 `dlopen`。
- 默认不内置浏览器（`BUILD_CHROMIUM=0`）；若设为 `1`，安装官方 Google Chrome DEB，而非 Ubuntu 的 Snap 过渡包。
- 注意：厂商自带的 `libldap_r-2.4.so.2` 仍引用旧版 `libgnutls.so.26`、`libgcrypt.so.11`，两者在 Ubuntu 24.04 中并非原生系统库。静态扫描未发现主进程直接依赖该 LDAP 库，但这**不代表该功能无风险**；遇到登录问题请先检查动态库实际加载记录。

### 从 main 切换到测试分支

**先备份** `runtime/data/root`、`.env` 和自定义脚本，切换 Git 分支前确认工作区没有未提交的改动。请不要将 DEB 或企业配置提交到 Git。

```bash
cd ~/docker/docker-atrust
git fetch origin ubuntu-24.04
git switch --track origin/ubuntu-24.04  # 首次切换
# 已有本地 ubuntu-24.04 分支则使用 git switch ubuntu-24.04
docker compose config -q

# 不安装可选浏览器的最小镜像
docker compose build --no-cache
bash tests/ubuntu-24.04-smoke.sh local/atrust:latest

# 确保 runtime/aTrustInstaller_amd64.deb 已存在
docker compose up -d --force-recreate
docker compose logs -f
```

如果需要容器内部的浏览器完成认证，将 `.env` 设置为 `BUILD_CHROMIUM=1`、`CHROMIUM=1` 再运行：

```bash
docker compose up -d --build --force-recreate
```

`BUILD_CHROMIUM=1` 使用 Google 官方 Chrome DEB：镜像体积可能明显增大，且构建时须访问 `dl.google.com`；`BUILD_CHROMIUM=0` 不依赖 Google 下载服务。请遵守官方 Chrome 软件许可和安全更新要求。

### 初步验证与回退

```bash
./check.sh
docker exec atrust cat /etc/os-release
docker exec atrust ldd /usr/share/sangfor/aTrust/resources/bin/aTrustAgent | grep -E 'not found|ssl|crypto|Qt5' || true
docker image inspect local/atrust:latest --format '{{.Size}}'
docker ps -s
```

`ldd` 适用于你从授权门户取得且可信的客户端文件；对不可信 ELF 不要运行它。**单纯构建和静态检查不代表 VPN 实际可登录。**

测试失败可切换回 `main` 并重新构建：

```bash
docker compose down
git switch main
git pull --ff-only origin main
docker compose up -d --build --force-recreate
```

切换分支不会删除唯一映射目录中的登录状态，但更换基础系统后仍须留意厂商的设备绑定/登录状态兼容性。

## 只有一个目录挂载

```text
docker-atrust/
├── Dockerfile
├── compose.yaml
├── build.sh
├── runtime/                              # 唯一宿主机挂载目录
│   ├── scripts/
│   │   ├── start.sh                      # 外挂容器入口脚本
│   │   └── install-atrust.sh             # 容器启动安装脚本
│   ├── aTrustInstaller_amd64.deb         # 自行放入，不提交 Git
│   └── data/
│       └── root/                        # aTrust、VNC、浏览器及登录状态
├── build-scripts/                        # 镜像内安装适配逻辑
├── docker-root/                          # aTrust/VNC/路由脚本
├── docker-root-preinst/
├── fake-getlogin/
└── fake-hwaddr/
```

唯一一条 Compose `volumes` 配置：

```yaml
volumes:
  - type: bind
    source: ./runtime
    target: /opt/atrust
```

此目录同时提供：

- `/opt/atrust/scripts/start.sh` 和 `install-atrust.sh`（容器入口脚本由宿主机提供）
- `/opt/atrust/aTrustInstaller_amd64.deb`（新容器启动时安装；不会 COPY 到镜像）
- `/opt/atrust/data/root`（持久化的 root HOME）

镜像构建时预置 `/root -> /opt/atrust/data/root` 符号链接，使 aTrust 根据用户数据库解析到 `/root` 时，仍将数据写入唯一挂载目录。容器启动时会自动创建目录、初始化基础 home 文件，并设置 `0700` 权限。

`devices: /dev/net/tun:/dev/net/tun` 是提供 VPN TUN 的**设备映射**，不是第二个目录挂载，仍必须保留。Compose 的 `.env` 从宿主机读取，并没有映射为文件或目录。

**安全权衡**：仅使用一个读写挂载意味着脚本、安装包与持久化数据位于同一个可写目录，无法像原方案那样把脚本和 DEB 分别以 `:ro` 方式挂载。请限制 `runtime/` 目录和 Docker 主机访问权限，不要在其中保存非必要密钥。此服务运行在可信受管理环境内。

## 准备与启动

先确认宿主机安装了 Docker Engine、Compose，并有 `/dev/net/tun`。

```bash
git clone https://github.com/timwai/docker-atrust.git
cd docker-atrust

# runtime/scripts/ 已经在 Git 中，不需要额外复制启动脚本
mkdir -p runtime/data/root
chmod 700 runtime runtime/data runtime/data/root

# 将获得授权的官方 aTrust AMD64 安装包放到唯一目录
cp /path/to/aTrustInstaller_amd64.deb runtime/aTrustInstaller_amd64.deb
chmod 600 runtime/aTrustInstaller_amd64.deb

cp .env.example .env
chmod 600 .env
nano .env   # VNC_PASSWORD 必须设置

docker compose up -d --build
docker compose logs -f
```

也可以直接 `./build.sh` 构建纯运行环境；`./build.sh --deb /path/to/aTrustInstaller_amd64.deb` 会将 DEB 放在宿主机的 `runtime/`，并构建同一个不含客户端的镜像。使用 `--official` 需自行确认有权使用官方公共包。

### 从旧版三挂载配置迁移

原版使用 `./data:/root`、`./scripts:/opt/atrust/scripts`、`./vendor/aTrustInstaller_amd64.deb:/opt/atrust/aTrustInstaller_amd64.deb`。更新前先备份，停掉旧容器，然后迁移：

```bash
# 在旧版仓库目录运行；优先备份 data/ 里的登录状态
docker compose down
cp -a data data.backup 2>/dev/null || true

git pull --ff-only origin main
mkdir -p runtime/data/root
# 复制原有 HOME 数据（切勿覆盖已有备份）
if [ -d data ]; then cp -an data/. runtime/data/root/; fi
if [ -f vendor/aTrustInstaller_amd64.deb ]; then
  cp -n vendor/aTrustInstaller_amd64.deb runtime/aTrustInstaller_amd64.deb
fi
chmod 700 runtime/data/root

# 现用启动脚本是 runtime/scripts/start.sh
docker compose up -d --build --force-recreate
docker compose logs -f
```

如果修改过旧 `scripts/start.sh`，请先备份并**人工合并**改动到 `runtime/scripts/start.sh`，不能直接用旧脚本覆盖新脚本，否则会失去单目录模式的 HOME 初始化逻辑。上面的迁移命令假定历史 `./data` 确实存储的是容器 `/root`。

### 日常使用

修改宿主机的 `runtime/scripts/start.sh` 后：

```bash
docker compose restart
```

换 DEB 后：

```bash
docker compose up -d --force-recreate
```

修改 Dockerfile 依赖后：

```bash
docker compose up -d --build --force-recreate
```

重启同一容器时按已安装包的 SHA256 跳过安装；删除并新建容器时，容器本身的文件系统重置并重新安装 aTrust。安装标记保存在容器文件系统内部，而不是持久化目录，防止重建误跳过安装。

### VNC 和网页认证

端口仅绑定宿主机 `127.0.0.1`：

| 容器端口 | 用途 |
| --- | --- |
| `5901/tcp` | TigerVNC |
| `54631/tcp` | aTrust 网页认证回调 |
| `8080/tcp` | 可选 noVNC（`.env` 设置 `USE_NOVNC=1`） |

```bash
ssh -L 5901:127.0.0.1:5901 -L 54631:127.0.0.1:54631 \
    -L 8080:127.0.0.1:8080 user@ubuntu-server
```

VNC Viewer 连接 `127.0.0.1:5901`，或开启 noVNC 后访问 `http://127.0.0.1:8080/vnc.html`。Ubuntu 24.04 的 `chromium-browser` 是 Snap 过渡包，无法像 Debian 的 Chromium 一样直接用于轻量容器；因此测试分支在 `BUILD_CHROMIUM=1` 时通过 HTTPS 安装 **Google Chrome 官方 AMD64 DEB**（有额外的服务条款并显著增大镜像）。启用浏览器还需设置 `CHROMIUM=1` 再重建镜像。VNC 传统密码最多使用前 8 位。

## 验证与排错

```bash
docker compose config
docker inspect atrust --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'
./check.sh
docker exec atrust curl -Iv https://your-authorized-intranet-host
```

`docker inspect` 应只显示一个 Bind 目录挂载，目标是 `/opt/atrust`；`/dev/net/tun` 是设备直通，不会计入目录挂载。

如果报缺少 DEB，确认 `runtime/aTrustInstaller_amd64.deb` 存在且为**普通文件**。如果认证失败，检查 `runtime/data/root` 是否正确持久化、`utun7` 接口和 aTrust 日志。只出现 `utun7` 并不意味着 VPN 已登录成功。Ubuntu 测试分支不使用 Debian 11 快照源。官方 DEB 自带 OpenSSL 1.1、LDAP 2.4、Qt5，但旧版 LDAP 组件引用 libgnutls.so.26/libgcrypt.so.11，是否运行时加载仍须验证。

当前源码已经能够进行静态检查，但尚未在本操作环境完成 Docker 全量构建以及实际 VPN 登录测试。


## aTrust 2.5.16.30 动态库依赖分析

分析单位门户下载的原始 **Ubuntu amd64** 官方 DEB（无需在宿主机安装 aTrust）。
分析脚本只执行 \`dpkg-deb -x\` 和 \`readelf\`，不执行官方程序，也不执行 preinst/postinst。

\`\`\`bash
sudo apt-get install -y python3 dpkg binutils
# 将正式安装包保存在唯一 runtime 目录：
python3 analyze-deps.py runtime/aTrustInstaller_amd64.deb
# 与已经构建的运行镜像比较（可选）：
python3 analyze-deps.py runtime/aTrustInstaller_amd64.deb \
  --image local/atrust:latest
\`\`\`

生成 \`runtime/data/atrust-dependencies.md\` 和
\`runtime/data/atrust-dependencies.json\`。前者是人类可读的依赖报告；
后者列出每个 ELF 的 \`DT_NEEDED\`，便于判断哪些旧库确实被使用。

**注意**：\`DT_NEEDED\` 不包含运行时 \`dlopen\` 或插件依赖；即使未发现
\`libssl.so.1.1\` 或 \`libldap_r-2.4.so.2\`，也不能直接证明删除旧库后一定可正常登录。
