FROM python:3.11-slim-bookworm

# 可选镜像源配置 (默认使用官方 CDN 源，保障 GitHub Actions 与全球快速拉取；本地构建可按需传入国内镜像源)
ARG APT_MIRROR=""
ARG PIP_INDEX_URL=""

RUN if [ -n "$APT_MIRROR" ]; then sed -i "s|deb.debian.org|$APT_MIRROR|g" /etc/apt/sources.list.d/debian.sources; fi && \
    apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    p7zip-full \
    unrar-free \
    curl \
    gosu \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 安装 Python 运行依赖
COPY server/requirements.txt requirements.txt
RUN if [ -n "$PIP_INDEX_URL" ]; then \
        pip install --no-cache-dir -i "$PIP_INDEX_URL" -r requirements.txt; \
    else \
        pip install --no-cache-dir -r requirements.txt; \
    fi

# 复制代码与启动配置
COPY server/src /app/src
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 暴露网关端口 (统一承载 MCP SSE 与 REST/WebSocket)
EXPOSE 8000

ENV PYTHONPATH=/app/src

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["python", "-m", "nasio.main"]
