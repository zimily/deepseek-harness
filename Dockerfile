# syntax=docker/dockerfile:1.7
# DeepSeek Harness (dsh) web UI: 基于 npm 包不构建源码。
# 参考 docs/.agents/notes/implemented/architecture 的源面/产物面分工；
# tini 作为 PID 1 转 SIGTERM/SIGINT 给 dsh (apps/cli/src/profile-boot.ts:221-222)。
FROM node:22-bookworm-slim

# tini = minimal init；node:22-bookworm-slim 没有自带。
# ca-certificates 让 DEEPSEEK_API_KEY 走的 https 验证链路完整。
# socat = bridge IP:3080 反向代理到 dsh 的 127.0.0.1:3080，绕过 dsh CLI 拒绝
# --host 0.0.0.0 的源码层限制（packages/bundle/web-app/src/startup.ts:96）。
# iproute2 让 entrypoint 能拿 eth0 IP；socat 必须绑 bridge IP 而不是 0.0.0.0，
# 否则会把 127.0.0.1:3080 盖住让 dsh 报 EADDRINUSE。
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      tini ca-certificates socat iproute2 \
 && rm -rf /var/lib/apt/lists/*

# 版本与仓库根 package.json 对齐（0.2.1-rc.3）。
# 用 npm 而非 pnpm：发布到 npm 的是 @deepseek-ai/dsh，npm 会按 optionalDependencies
# 拉对应当前平台的 node-addon-require-builtin prebuild
# （see apps/cli/package.json:83）。
RUN npm install -g @deepseek-ai/dsh@0.2.1-rc.3 \
 && npm cache clean --force

ENV NODE_ENV=production \
    DSH_HOME=/dsh/home \
    npm_config_update_notifier=false

WORKDIR /dsh
# 用 root 建好目录再切 node；DSH_HOME 由 packages/util/home-paths 解析（默认 ~/.dsh）
RUN mkdir -p /dsh/home \
 && chown -R node:node /dsh

COPY --chown=node:node entrypoint.sh /usr/local/bin/dsh-entrypoint.sh
RUN chmod +x /usr/local/bin/dsh-entrypoint.sh

USER node

EXPOSE 3080

# entrypoint.sh 做两件事：先起 socat 反代桥（容器 eth0 IP:3080 → dsh 的
# 127.0.0.1:3080），再 exec tini 当 PID 1 把 SIGTERM/SIGINT 转给 dsh。
ENTRYPOINT ["/usr/local/bin/dsh-entrypoint.sh"]
CMD ["dsh", "web", "--no-open"]
