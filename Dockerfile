# aTrust self-contained source build; no GitHub checkout at image build time.
FROM debian:bookworm-slim AS tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc make libc6-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY fake-getlogin /src/fake-getlogin
COPY fake-hwaddr /src/fake-hwaddr
RUN make -C /src/fake-getlogin && make -C /src/fake-hwaddr && \
    mkdir -p /results/usr/local/lib && \
    cp /src/fake-getlogin/fake-getlogin.so /results/usr/local/lib/ && \
    cp /src/fake-hwaddr/fake-hwaddr.so /results/usr/local/lib/

FROM debian:bookworm-slim
ARG CHROMIUM=0
ARG DEBIAN_FRONTEND=noninteractive
COPY build-scripts/config-apt.sh /tmp/build-scripts/config-apt.sh
RUN . /tmp/build-scripts/config-apt.sh && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates libx11-xcb1 libnss3 libasound2 iptables \
      xclip libxtst6 dante-server tigervnc-standalone-server \
      tigervnc-tools psmisc flwm x11-utils busybox libssl-dev \
      iproute2 tinyproxy-bin libxss1 fonts-wqy-microhei \
      socat wget procps libssl1.1 libatk-bridge2.0-0 \
      libgtk-3-0 libgbm1 libqt5x11extras5 \
      libqt5core5a libqt5network5 libqt5widgets5 \
      libldap-2.4-2 stalonetray libproxy1v5 \
      novnc websockify dbus-x11 && \
    if [ "$CHROMIUM" = 1 ]; then \
      apt-get install -y --no-install-recommends chromium; \
    fi && \
    rm -rf /var/lib/apt/lists/*
RUN groupadd -r socks && useradd -r -g socks socks
COPY docker-root-preinst /
COPY build-scripts/install-vpn-gui.sh build-scripts/get-echost-names.sh /tmp/build-scripts/
COPY vendor/aTrustInstaller_amd64.deb /tmp/VPN.deb
ENV VPN_TYPE=ATRUST
RUN chmod +x /tmp/build-scripts/install-vpn-gui.sh && \
    /tmp/build-scripts/install-vpn-gui.sh
COPY docker-root /
COPY --from=tooling /results/ /
RUN ln -sf novnc-min-size.sh /usr/local/bin/novnc && \
    chmod +x /usr/local/bin/start.sh
ENV PING_INTERVAL=1800
VOLUME ["/root"]
EXPOSE 5901 1080 8888 54631 8080
CMD ["/usr/local/bin/start.sh"]
