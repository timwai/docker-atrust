# docker-atrust

在 Ubuntu Server（amd64）等无宿主机桌面环境下，以 Docker 运行深信服 aTrust Linux 客户端。

**当前设计（2026-10）：** Docker 镜像只包含 Debian 运行依赖和开源辅助程序；**aTrust DEB 不进入镜像**，在每个新容器第一次启动时由挂载的脚本安装。整个服务**没有 SOCKS5 或 HTTP 正向代理**，仅提供 VNC 登录界面、可选 noVNC 和 aTrust 官方网页认证回调。

> 非官方社区衍生项目。使用企业 VPN 前请获得单位授权；客户端的合法使用、身份验证、多因素认证与终端管理策略依旧适用。请勿把企业特定 DEB、账号、证书或登录配置提交至公开仓库。

## 来源与许可证

本项目代码最初基于 [docker-easyconnect/docker-easyconnect](https://github.com/docker-easyconnect/docker-easyconnect) 调整，最初导入参考版本为 [`e8fc56a7c518d83b6817e16713f765e3c652e3bf`](https://github.com/docker-easyconnect/docker-easyconnect/commit/e8fc56a7c518d83b6817e16713f765e3c652e3bf)。

- **上游作者及贡献者**：docker-easyconnect / Hagb 等贡献者。
- **上游开源代码许可证**：WTFPL v2，原文保留于 [LICENSE.txt](LICENSE.txt)。仓库衍生脚本同样按该许可证发布。
- **aTrust 客户端**：深信服 Sangfor 的专有软件，其版权、许可、商标及企业部署政策不受本仓库开源许可证覆盖，本仓库不分发 aTrust DEB。
- **其他依赖**：Debian、TigerVNC、noVNC、Websockify 等分别遵循其自身许可证。

相对于上游，此仓库已经取消了 EasyConnect、Dante SOCKS5、Tinyproxy HTTP 代理及下载其他 GitHub 项目进行构建的流程；运行和安装所需开源代码已保存在当前仓库。构建仍需下载 Debian 基础镜像和 APT 依赖；只有明确指定 `--official` 才会下载深信服公共 DEB，不构成完全离线构建。

## 目录与启动流程

```text
docker-atrust/
├── Dockerfile                         # Debian 12 + aTrust 依赖；不装客户端
├── compose.yaml                       # bind mount 启动脚本与 DEB
├── build.sh                           # 构建通用运行时镜像、可选准备 DEB
├── scripts/
│   ├── start.sh                       # 外挂入口脚本，修改后无需重建镜像
│   └── install-atrust.sh              # 容器启动时执行 DEB 安装
├── build-scripts/install-vpn-gui.sh   # 与 aTrust 兼容的包安装逻辑
├── docker-root/                       # aTrust Agent、VNC、路由相关脚本
├── docker-root-preinst/               # aTrust 容器兼容组件
├── fake-getlogin/                     # 来自上游的本地 C 辅助组件
├── fake-hwaddr/                       # 来自上游的本地 C 辅助组件
├── vendor/
│   └── aTrustInstaller_amd64.deb      # 自行准备，不会提交 GitHub/打进镜像
└── data/                              # 运行数据（宿主机持久化，不提交 GitHub）
```

启动过程：

1. Compose 以只读 bind mount 把 `./scripts` 放入 `/opt/atrust/scripts`，把 DEB 放入 `/opt/atrust/aTrustInstaller_amd64.deb`。
2. 容器入口执行 `/bin/bash /opt/atrust/scripts/start.sh`。
3. 入口调用 `install-atrust.sh`，执行官方包的 preinst/postinst；同一容器内按 DEB SHA256 跳过重复安装。**镜像里没有 aTrust 安装文件。**
4. 创建独立 `utun7`（之前由 Dante 提前创建），启动 VNC/可选 noVNC、aTrust Agent 和登录界面。
5. 容器重启时复用已安装的客户端；容器**删除重建**后重新安装。更换 DEB 时需要重新创建容器。

## 环境

- Ubuntu Server amd64 / Docker Engine 和 Docker Compose。
- `/dev/net/tun` 可用，容器具备 `NET_ADMIN`。
- `vendor/aTrustInstaller_amd64.deb` 必须是获得合法授权的 AMD64 aTrust 安装包，且必须在创建容器**之前**存在并且是普通文件。
- 宿主机无需 X11、Wayland 或 GNOME；容器内部通过 TigerVNC 提供图形化登录。
- PVE LXC 嵌套 Docker 可能遇到 AppArmor/runc 或 TUN 限制，建议优先使用 KVM 虚拟机。

## 安装与启动

```bash
git clone https://github.com/timwai/docker-atrust.git
cd docker-atrust

# 放入已从企业门户或厂商获得的正版客户端
mkdir -p vendor data
cp /path/to/aTrustInstaller_amd64.deb vendor/
chmod 700 data

cp .env.example .env
chmod 600 .env
# 编辑 VNC_PASSWORD（VNC 协议传统密码最多使用前8个字符）
nano .env

# 构建的是“运行环境”，不是打包好的 aTrust 客户端
docker compose build

# 创建容器时安装挂载的 aTrust DEB，随后启动客户端
docker compose up -d
docker compose logs --tail=100 -f
```

也可运行 `./build.sh` 构建通用镜像；`./build.sh --deb /path/to/aTrustInstaller_amd64.deb` 会将 DEB **保存在宿主机** `vendor/` 后构建镜像（不会 COPY 到镜像中）。要从厂商公开 CDN 获取 2.5.16.30 的测试包，可显式使用 `./build.sh --official`（可通过 `ATRUST_VERSION` 自定义版本；优先使用企业门户包）。

### 升级或调整

**修改外部启动脚本**（如 `scripts/start.sh`）：修改宿主机文件后执行 `docker compose restart`，无需构建镜像。请勿把脚本、DEB 或数据目录映射为可从容器修改的读写挂载。

**更新 aTrust DEB**：替换宿主机 `vendor/aTrustInstaller_amd64.deb`，然后：

```bash
docker compose up -d --force-recreate
```

新容器会在启动时安装新版本。单纯 `docker compose restart` 复用旧容器文件系统，不会自动执行包覆盖升级；哈希不一致时会提示重新创建容器。

**修改 Dockerfile 或依赖包**：执行 `docker compose up -d --build --force-recreate`。

### Chrome 内置认证与 noVNC

如需容器内部 Chromium 以处理厂商网页认证，设置 `.env`：

```ini
BUILD_CHROMIUM=1
CHROMIUM=1
```

然后执行 `docker compose up -d --build --force-recreate`。

如需浏览器远程查看图形界面，设置 `USE_NOVNC=1` 并 `docker compose up -d`。noVNC 本身不是 HTTP **代理**；它只通过 8080 提供 VNC 网页。

## 网络端口

| 容器端口 | 作用 |
| --- | --- |
| `5901/tcp` | TigerVNC 登录界面 |
| `54631/tcp` | aTrust 官方浏览器认证回调（容器内由 socat/iptables 仅转发至本机客户端） |
| `8080/tcp` | 可选 noVNC 网页界面 |

**没有 1080 SOCKS5 或 8888 HTTP 代理服务，也不通过宿主机自动共享 VPN 流量。** Compose 将所有端口绑定到宿主机 `127.0.0.1`，不允许直接向公网开放。通过 SSH 使用：

```bash
ssh -L 5901:127.0.0.1:5901 -L 54631:127.0.0.1:54631 \
    -L 8080:127.0.0.1:8080 user@ubuntu-server
```

VNC Viewer 连接 `127.0.0.1:5901`，或启用 noVNC 后访问 `http://127.0.0.1:8080/vnc.html`。

## 验证

```bash
./check.sh
# 已经成功通过 VNC 登录后，在容器自己的 VPN 网络环境中测试授权资源
./check.sh https://your-authorized-intranet-host
```

确认 VPN 认证成功后，从容器内直连网络测试，不使用代理：

```bash
docker exec atrust ip -br address
docker exec atrust ip route
docker exec atrust curl -Iv https://your-authorized-intranet-host
```

仅有 `utun7` 接口或 VNC 端口监听不代表成功连接 VPN。

## 排错

- **首次启动报缺少 DEB**：确保 `vendor/aTrustInstaller_amd64.deb` 是已存在的普通文件；Docker 对不存在的文件型 bind mount 可能导致错误目录。
- **运行时报权限错误**：检查 `/tmp`、`/tmp/aTrustShell.conf` 所有者；请勿关闭登录检查或禁用企业认证。
- **`FIB table does not exist`**：首次清理空策略路由表的非致命提示，与业务 VPN 是否可用应分别验证。
- **`libssl1.1` / `libldap-2.4-2`**：仍从签名校验的 Debian 11 历史快照获取，相关旧组件的安全维护风险应结合厂商新版本再评估。快照配置在 `build-scripts/config-apt.sh`。
- **登录正常但内网不通**：检查容器内 `ip route` 和 `utun7`，并用授权内网 IP/域名直连，不再查找或配置 1080/8888。
- **容器恢复**：`docker compose logs -f`，同一容器重启不会重复安装；容器重建需要挂载的 DEB 可读。
- **构建与运行验证状态**：源码与脚本已提交，尚未在此执行环境完成 Docker 实际构建及单位 VPN 认证验证。

## 项目许可证

上游代码衍生部分保留 [LICENSE.txt](LICENSE.txt)（WTFPL v2），aTrust 官方客户端及企业专用配置不属于该开源许可证范畴。
