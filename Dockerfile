# Ubuntu 24.04 LTS runtime for aTrust 2.5.16.30 (AMD64).
# Proprietary aTrust installer is mounted at container startup, not baked into this image.
FROM ubuntu:24.04 AS tooling
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates gcc make libc6-dev && \
    rm -rf /var/lib/apt/lists/*
COPY fake-getlogin /src/fake-getlogin
COPY fake-hwaddr /src/fake-hwaddr
RUN make -C /src/fake-getlogin && make -C /src/fake-hwaddr && \
    mkdir -p /results/usr/local/lib && \
    cp /src/fake-getlogin/fake-getlogin.so /results/usr/local/lib/ && \
    cp /src/fake-hwaddr/fake-hwaddr.so /results/usr/local/lib/

FROM ubuntu:24.04
ARG CHROMIUM=0
ARG DEBIAN_FRONTEND=noninteractive
# The official DEB already bundles OpenSSL 1.1, LDAP 2.4 and Qt5.
# X11, XCB, GTK and VNC dependencies provide the external SONAMEs
# observed in the user's Ubuntu 2.5.16.30 package scan.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates bash dpkg passwd \
      curl wget busybox psmisc procps \
      iptables iproute2 socat \
      tigervnc-standalone-server tigervnc-tools \
      flwm stalonetray xclip x11-utils xauth \
      fonts-wqy-microhei novnc websockify dbus-x11 \
      libx11-xcb1 libx11-6 libxext6 libxtst6 libxss1 \
      libxcomposite1 libxdamage1 libxrandr2 libxrender1 libxi6 \
      libice6 libsm6 \
      libxcb-dri3-0 libxcb-icccm4 libxcb-image0 \
      libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 \
      libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 \
      libxcb-xfixes0 libxcb-xkb1 libxkbcommon-x11-0 \
      libgtk-3-0t64 libatk-bridge2.0-0t64 \
      libgbm1 libgl1 libnss3 libasound2t64 libcups2t64 \
      libproxy1v5 && \
    rm -rf /var/lib/apt/lists/*

# Ubuntu's chromium-browser is a Snap transitional package. When explicitly
# requested (CHROMIUM=1), use Google's official Chrome DEB instead.
# This is optional and adds significant image size; Chrome terms apply.
RUN if [ "$CHROMIUM" = "1" ]; then \
      mkdir -p /etc/default && touch /etc/default/google-chrome && \
      curl -fL --retry 3 --connect-timeout 20 \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/google-chrome.deb && \
      apt-get update && \
      apt-get install -y --no-install-recommends /tmp/google-chrome.deb && \
      rm -f /tmp/google-chrome.deb /etc/apt/sources.list.d/google-chrome.list && \
      rm -rf /var/lib/apt/lists/* && \
      command -v google-chrome-stable; \
    elif [ "$CHROMIUM" != "0" ]; then \
      echo "Invalid CHROMIUM=$CHROMIUM (expected 0 or 1)" >&2; exit 1; \
    fi

COPY docker-root-preinst /
COPY build-scripts/install-vpn-gui.sh build-scripts/get-echost-names.sh /tmp/build-scripts/
COPY docker-root /
COPY --from=tooling /results/ /
RUN ln -sf novnc-min-size.sh /usr/local/bin/novnc && \
    mv /root /root.image && \
    ln -s /opt/atrust/data/root /root
ENV VPN_TYPE=ATRUST
EXPOSE 5901 54631 8080
ENTRYPOINT ["/bin/bash", "/opt/atrust/scripts/start.sh"]
