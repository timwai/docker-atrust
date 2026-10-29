# docker-atrust

无需宿主机图形桌面，在 Ubuntu Server（amd64）上通过 Docker 使用深信服 aTrust Linux 客户端。

**当前设计：所有需要持久化或外挂的内容，只映射一个宿主机目录 `./runtime:/opt/atrust`。** 不内置 aTrust 官方 DEB；新容器启动时从该目录安装。没有 SOCKS5/HTTP 正向代理，保留 VNC、可选 noVNC 和厂商网页登录回调。网络模式仍为 Docker Compose 默认 bridge，不共享宿主机网络。

> 本工程为非官方社区衍生项目，与深信服及相关运营商无隶属关系。使用企业 VPN 前请确认授权；不提供规避厂商认证、MFA 或终端安全控制的功能。请不要公开企业专属 DEB、配置、证书及登录数据。

## 来源与许可证

本项目基于 [docker-easyconnect/docker-easyconnect](https://github.com/docker-easyconnect/docker-easyconnect) 改造，最初导入的上游源码版本是 [`e8fc56a7c518d83b6817e16713f765e3c652e3bf`](https://github.com/docker-easyconnect/docker-easyconnect/commit/e8fc56a7c518d83b6817e16713f765e3c652e3bf)。致谢原作者 Hagb 及 docker-easyconnect 贡献者，保留 [LICENSE.txt](LICENSE.txt)（WTFPL v2）。本仓库的开源许可**不覆盖**深信服 aTrust 专有客户端、商标或其下载包；Debian、TigerVNC、noVNC 等仍适用各自许可证。

本项目将用到的上游辅助脚本和 C 源文件直接收录在当前仓库，镜像构建阶段不克隆其他 GitHub 仓库。构建仍需要 Debian 基础镜像与 Debian APT 仓库；明确使用 `--official` 时还需深信服官方 CDN。

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

VNC Viewer 连接 `127.0.0.1:5901`，或开启 noVNC 后访问 `http://127.0.0.1:8080/vnc.html`。需要浏览器时把 `BUILD_CHROMIUM=1`、`CHROMIUM=1` 写入 `.env`，再重建镜像。VNC 传统密码最多使用前 8 位。

## 验证与排错

```bash
docker compose config
docker inspect atrust --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'
./check.sh
docker exec atrust curl -Iv https://your-authorized-intranet-host
```

`docker inspect` 应只显示一个 Bind 目录挂载，目标是 `/opt/atrust`；`/dev/net/tun` 是设备直通，不会计入目录挂载。

如果报缺少 DEB，确认 `runtime/aTrustInstaller_amd64.deb` 存在且为**普通文件**。如果认证失败，检查 `runtime/data/root` 是否正确持久化、`utun7` 接口和 aTrust 日志。只出现 `utun7` 并不意味着 VPN 已登录成功。本工程仍使用旧版 Debian 11 兼容库历史快照，它们可能存在不再更新的安全风险。

当前源码已经能够进行静态检查，但尚未在本操作环境完成 Docker 全量构建以及实际 VPN 登录测试。
