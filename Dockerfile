# syntax=docker/dockerfile:1.7
# DeepSeek Harness (dsh) web UI: 基于 npm 包不构建源码。
# 参考 docs/.agents/notes/implemented/architecture 的源面/产物面分工；
# tini 作为 PID 1 转 SIGTERM/SIGINT 给 dsh (apps/cli/src/profile-boot.ts:221-222)。
FROM node:22-bookworm-slim

# tini = minimal init；node:22-bookworm-slim 没有自带。
# ca-certificates 让 DEEPSEEK_API_KEY 走的 https 验证链路完整。
RUN apt-get update \
 && apt-get install -y --no-install-recommends tini ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 版本与仓库根 package.json 对齐（0.1.0-rc.5）。
# 用 npm 而非 pnpm：发布到 npm 的是 @deepseek-ai/dsh，npm 会按 optionalDependencies
# 拉对应当前平台的 node-addon-require-builtin prebuild
# （see apps/cli/package.json:83）。
RUN npm install -g @deepseek-ai/dsh@0.1.0-rc.5 \
 && npm cache clean --force

ENV NODE_ENV=production \
    DSH_HOME=/dsh/home \
    npm_config_update_notifier=false

WORKDIR /dsh
# 用 root 建好目录再切 node；DSH_HOME 由 packages/util/home-paths 解析（默认 ~/.dsh）
RUN mkdir -p /dsh/home \
 && chown -R node:node /dsh

USER node

# dsh web 默认 127.0.0.1:3080（packages/bundle/web-app/src/startup.ts:47-79）。
# 显式写出，避免任何行级配置把它换成 0.0.0.0 —— 当前版本源码层拒绝（apps/cli/tests/built-bin.e2e.ts:348）。
EXPOSE 3080

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["dsh", "web", "--host", "127.0.0.1", "--port", "3080"]
