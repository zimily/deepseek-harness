#!/bin/sh
# Docker entrypoint for dsh-web.
#
# 为什么需要这个脚本（vs 直接用 ENTRYPOINT ["/usr/bin/tini", "--"]）：
#   dsh CLI 在 0.2.1-rc.2 拒绝 --host 0.0.0.0
#   （packages/bundle/web-app/src/startup.ts:96："unspecified (wildcard)
#   address... binding every interface would expose remote code execution
#   to the network"），并且源码层 hardcoded 只接受 '127.0.0.1' / '0.0.0.0'
#   （packages/host/webserver/src/index.ts:61）。
#   Docker Desktop on Windows + NAT 端口转发对 127.0.0.1 监听器不工作
#   （实测：容器内 0.0.0.0:3090 经 NAT 也连不到 host；docker-proxy + WinNAT
#   在该平台有 loopback RST bug）。所以让 dsh 仍默认 listen loopback，
#   外层 socat listen 在 0.0.0.0:3080，反向代理到 dsh 的 127.0.0.1:3080。
#   dsh web 仍要求 ?token= 做认证（packages/bundle/web-app/README.zh.md:65）。
#
#   这个约定是社区方案：见 geeknote.net/Rei/posts/3430（node:24 + socat）。
#   比改 cordis patch overlay（plugin tree `id:` / `name:` 语义复杂）稳。

set -eu

# 拿到容器的 bridge 接口 IP（不是 127.0.0.1）；socat 必须绑到这个 IP，
# 否则 0.0.0.0:3080 会盖住 dsh 期待的 127.0.0.1:3080，触发 EADDRINUSE。
HOST_IP=$(ip -4 addr show dev eth0 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
if [ -z "$HOST_IP" ]; then
  echo "[entrypoint] WARN: no eth0 IP found; socat fallback to 0.0.0.0" >&2
  BIND_ARG=
else
  echo "[entrypoint] socat will bind on $HOST_IP:3080 -> 127.0.0.1:3080" >&2
  BIND_ARG="bind=$HOST_IP"
fi

# socat fork-and-proxy container IP:3080 -> dsh 的 127.0.0.1:3080。
# fork + reuseaddr 防止 TIME_WAIT 阻塞重启。
# setsid 让 socat 进入新会话，避免后续 exec tini 后被 SIGTERM 牵连。
# 不要用 `disown`：dash 没有这个内建。
setsid socat TCP-LISTEN:3080,$BIND_ARG,fork,reuseaddr TCP:127.0.0.1:3080 \
  </dev/null >/dev/null 2>&1 &

# tini 当 PID 1 捕获 SIGTERM/SIGINT，再转给 dsh（apps/cli/src/profile-boot.ts:221-222）。
exec /usr/bin/tini -- "$@"
