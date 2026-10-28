FROM python:3.11-slim-bookworm

# 替换国内 Debian 软件源并安装系统级多媒体与解压依赖
RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources && \
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
RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt

# 复制代码与启动配置
COPY server/src /app/src
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 暴露网关端口 (统一承载 MCP SSE 与 REST/WebSocket)
EXPOSE 8000

ENV PYTHONPATH=/app/src

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["python", "-m", "nasio.main"]
