#!/bin/sh
# Debian websockify/noVNC: no external GitHub download at build time.
exec websockify --web=/usr/share/novnc 0.0.0.0:8080 127.0.0.1:5901
