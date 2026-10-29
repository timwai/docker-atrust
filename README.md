# docker-atrust

在 **Ubuntu Server amd64（无需宿主机桌面）** 内使用 Docker 构建和运行深信服 **aTrust** Linux 客户端，支持 VNC、可选 noVNC、SOCKS5 与 HTTP 代理。镜像内有轻量图形界面；这并不是 aTrust 官方提供的纯命令行登录客户端。

> 本项目为非官方社区衍生工程，与深信服、中国移动及其分公司没有隶属关系。访问企业 VPN 前请确保获得组织授权。**不提供绕过身份认证、MFA 或终端接入控制的功能。**

## 来源与致谢

本项目基于 [docker-easyconnect/docker-easyconnect](https://github.com/docker-easyconnect/docker-easyconnect) 的开源代码修改和精简。

- **上游项目**：https://github.com/docker-easyconnect/docker-easyconnect
- **代码导入所参考的上游版本**：[`e8fc56a7c518d83b6817e16713f765e3c652e3bf`](https://github.com/docker-easyconnect/docker-easyconnect/commit/e8fc56a7c518d83b6817e16713f765e3c652e3bf)
- **上游作者与贡献者**：docker-easyconnect / Hagb 及所有贡献者（保留上游 `LICENSE.txt`）。
- **上游开源许可证**：WTFPL v2（见 [LICENSE.txt](LICENSE.txt)）。从上游导入的文件及本仓库相应改动遵循该许可证；其它 Debian 依赖软件包仍适用其各自的许可。
- **aTrust 客户端**：深信服 Sangfor 的**专有软件**；其授权、版权和使用限制完全独立于本仓库的开源许可证。本仓库**不包含** aTrust DEB、镜像二进制文件或企业专用安装包。
- **运行依赖**：Debian、TigerVNC、Dante、Tinyproxy、noVNC 和 Websockify 等软件由 Debian 软件仓库安装，并各自遵循相应许可证。

### 与上游的主要区别

1. **不在构建时克隆 GitHub 项目**：所有需要的上游运行脚本、C 源文件及 Docker 配置已提交到本仓库；不使用 git submodule。
2. 单个多阶段 `Dockerfile` 在本地编译 `fake-getlogin`、`fake-hwaddr` 等辅助代码。不再下载上游的 tooling 镜像，也不再从 GitHub 下载并现场编译 noVNC/Websockify/Tinyproxy；这些网络服务直接使用 Debian 软件包。
3. 通过 `./build.sh --deb /path/to/aTrustInstaller_amd64.deb` 使用**本地官方安装包**构建，不依赖固定的 aTrust 版本。也提供 `--official` 从官方公共 CDN 下载供有权限的测试环境使用。
4. 修正策略路由初始化：先读取 `vpn-config.sh` 定义的 `VPN_TUN`，再执行 `detect-route.sh`；处理容器无法提升 `ulimit` 时的非致命报错。
5. 基础镜像为 **Debian 12 bookworm-slim**。由于 aTrust 仍使用部分 Debian 11 库，`build-scripts/config-apt.sh` 配置了有签名的 Bullseye 快照仓库，避免历史 `libssl1.1` 包 404。
6. 默认将 VNC 和代理端口仅绑定宿主机的 `127.0.0.1`，通过 SSH 转发访问。

**“不依赖外部仓库”的范围**：构建过程不克隆、引用或下载任何其他 GitHub *源码仓库*；但首次构建仍需拉取 Debian 基础镜像、安装 Debian APT 依赖，若指定 `--official` 还会从深信服 CDN 下载客户端。要完全离线构建，须另行准备基础镜像、APT 镜像和官方 DEB。

## 目录

```text
.
├── Dockerfile                   # 运行镜像 + 本地 C 工具编译
├── build.sh                     # 本地/官方 DEB 构建入口
├── compose.yaml                 # 容器运行、网络和端口
├── check.sh                     # 诊断与内网访问测试
├── build-scripts/               # 已纳入仓库的安装/依赖脚本
├── docker-root/                 # 上游 aTrust/VNC/代理启动与配置
├── docker-root-preinst/         # aTrust 安装时的兼容文件
├── fake-getlogin/               # 上游 C 辅助库
├── fake-hwaddr/                 # 上游 C 辅助库
├── vendor/                      # 放置官方 DEB；被 .gitignore 排除
└── LICENSE.txt                  # 上游项目许可证
```

## 安装环境

推荐 Ubuntu Server 22.04 或 24.04 的 amd64 主机（容器基础镜像仍为 Debian 12），已安装 Docker Engine、Compose 插件、`dpkg-deb` 和 `curl`；主机需要可用的 `/dev/net/tun`。如在 PVE LXC 内运行嵌套 Docker，可能需要解决宿主机 AppArmor/runc 和 TUN 的兼容问题，优先建议使用 KVM 虚拟机。

```bash
uname -m
ls -l /dev/net/tun
docker version
docker compose version
```

## 构建

克隆**本仓库本身一次**后，后续镜像构建不再执行 `git clone`：

```bash
git clone https://github.com/timwai/docker-atrust.git
cd docker-atrust
chmod +x build.sh check.sh
```

方式一：优先使用组织门户下载的官方 Linux AMD64 DEB（不要把 DEB 提交到公开 GitHub 仓库）：

```bash
./build.sh --deb /path/to/aTrustInstaller_amd64.deb
```

方式二：有权使用 Sangfor 公共包时，下载 2.5.16.30（版本可以通过 `ATRUST_VERSION` 更改）：

```bash
./build.sh --official
```

认证需要内置 Chromium 时：

```bash
./build.sh --deb /path/to/aTrustInstaller_amd64.deb --chromium
```

或者把 DEB 放在 `vendor/aTrustInstaller_amd64.deb` 并使用：

```bash
./build.sh --local
```

产物为 `local/atrust:latest` 和 `local/atrust:<DEB版本>-amd64`。完整客户端版本由 `dpkg-deb` 实际读取，不假定门户版本等同于公共 CDN 版本。

## 运行

```bash
cp .env.example .env
chmod 600 .env
# 修改 .env 中的 VNC_PASSWORD；经典 VNC 密码最多取前 8 个字符
mkdir -p data && chmod 700 data
docker compose up -d
docker compose logs --tail=100 -f
```

宿主机不需要安装图形桌面。建议在管理电脑通过 SSH 转发：

```bash
ssh -L 5901:127.0.0.1:5901 -L 54631:127.0.0.1:54631 \
    -L 1080:127.0.0.1:1080 -L 8888:127.0.0.1:8888 \
    user@ubuntu-server
```

VNC Viewer 连接 `127.0.0.1:5901`；若在 `.env` 中设置 `USE_NOVNC=1`，可以同时转发宿主机 8080 端口并在浏览器中打开 `http://127.0.0.1:8080/vnc.html`。所有端口默认只绑定到宿主机回环地址，不应暴露公网。

若使用带 Chromium 的构建，在 `.env` 中设置 `CHROMIUM=1`。上游为了兼容某些客户端在容器中使用 `--no-sandbox` 启动 Electron/Chromium，意味着防护弱于正常沙箱环境；建议仅限经审批的可信场景。

VPN 建立后，检查本机代理端口和授权的内网 HTTPS 资源：

```bash
./check.sh
./check.sh https://your-authorized-intranet-host
curl -Iv --socks5-hostname 127.0.0.1:1080 https://your-authorized-intranet-host
```

仅有 `utun7` 网卡或 SOCKS5 端口监听并不代表已完成 VPN 认证；必须能正常访问授权的内网资源。

## 重要说明与排错

- **`libssl1.1` / `libldap-2.4-2`**：部分 aTrust 客户端依赖 Debian 11 的兼容库。当前构建固定历史快照以改善可复现性，但历史库可能缺少安全更新；应定期审计，并优先使用厂商支持的更新版本。
- **APT GPG**：保持签名验证，不采用 `trusted=yes` 或 `--allow-unauthenticated`。如遇 `invalid signature`，先检查磁盘、代理网关、Docker/runc/seccomp。
- **aTrustShell.conf Permission denied**：先检查容器内 `/tmp` 权限与文件属主。不要直接将整个目录设置为 `777` 或跳过身份认证。
- **路由异常**：查看 `docker exec atrust ip rule`、`ip route show table 2`，以及 `utun7` 状态；当前版本已调整 VPN 配置加载顺序。
- **代理访问**：容器的 SOCKS5/HTTP 端口默认不是全局 VPN 网关。企业内网的账号、认证令牌和设备绑定状态均不得写入此仓库或镜像标签。
- **未经验证**：仓库内容已提交并可供静态检查，但尚未在当前执行环境中完成 Docker 镜像真实构建和四川移动 VPN 登录验证。相关网络策略、软件兼容性仍应以你的实际环境测试为准。

## 许可证

原上游源文件和本仓库新加的开源构建脚本按 [LICENSE.txt](LICENSE.txt) 中的 WTFPL v2 使用；深信服 aTrust 本身及其安装包、商标、配置和企业账号不在该授权范围。保留原始项目链接是为了明确项目来源和向作者致谢。
