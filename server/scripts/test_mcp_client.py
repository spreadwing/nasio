import os
import json
import threading
import time
import urllib.request

BASE_URL = os.getenv("NASIO_URL", "http://localhost:8000")
TOKEN = os.getenv("NASIO_TOKEN", "your_secure_random_token_here")

session_id = None
endpoint = None
received_messages = []


def sse_listener():
    global session_id, endpoint
    req = urllib.request.Request(f"{BASE_URL}/sse")
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Host", "localhost:8000")

    with urllib.request.urlopen(req) as resp:
        for line in resp:
            line = line.decode("utf-8").strip()
            if line.startswith("data:"):
                data = line[5:].strip()
                if "/messages/" in data:
                    endpoint = data
                    print(f"[*] SSE Connected! Endpoint: {endpoint}")
                else:
                    try:
                        parsed = json.loads(data)
                        print(f"\n[<== Server SSE Message]:\n{json.dumps(parsed, ensure_ascii=False, indent=2)}")
                    except Exception:
                        print(f"\n[<== Server SSE Raw]: {data}")


# 启动后台监听线程
t = threading.Thread(target=sse_listener, daemon=True)
t.start()

# 等待 session 初始化
for _ in range(20):
    if endpoint:
        break
    time.sleep(0.2)

if not endpoint:
    print("[-] Failed to get SSE session endpoint")
    exit(1)


def send_rpc(msg):
    url = f"{BASE_URL}{endpoint}"
    payload = json.dumps(msg).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Host", "localhost:8000")
    with urllib.request.urlopen(req) as resp:
        return resp.status, resp.read().decode("utf-8")


# 1. 发送 initialize
init_msg = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "test-client", "version": "1.0.0"},
    },
}
print("\n=== 1. 初始化 MCP 协议 ===")
status, res = send_rpc(init_msg)
print(f"Status: {status}, Response: {res}")

# 2. 列出所有注册的 Tools
tools_msg = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
print("\n=== 2. 列出注册的 MCP Tools ===")
status, res = send_rpc(tools_msg)
print(f"Status: {status}, Response: {res[:500]}...")

# 3. 调用 get_system_status
call_status = {
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {"name": "get_system_status", "arguments": {}},
}
print("\n=== 3. 调用工具 get_system_status ===")
status, res = send_rpc(call_status)
print(f"Status: {status}, Response: {res}")

# 4. 调用 get_mcp_config
call_config = {
    "jsonrpc": "2.0",
    "id": 4,
    "method": "tools/call",
    "params": {"name": "get_mcp_config", "arguments": {}},
}
print("\n=== 4. 调用工具 get_mcp_config ===")
status, res = send_rpc(call_config)
print(f"Status: {status}, Response: {res}")

# 5. 调用 list_trash_files
call_trash = {
    "jsonrpc": "2.0",
    "id": 5,
    "method": "tools/call",
    "params": {"name": "list_trash_files", "arguments": {}},
}
print("\n=== 5. 调用工具 list_trash_files ===")
status, res = send_rpc(call_trash)
print(f"Status: {status}, Response: {res}")

# 6. 调用 test_downloader_connection (qbittorrent)
call_qb = {
    "jsonrpc": "2.0",
    "id": 6,
    "method": "tools/call",
    "params": {"name": "test_downloader_connection", "arguments": {"downloader_type": "qbittorrent"}},
}
print("\n=== 6. 调用工具 test_downloader_connection (qbittorrent) ===")
status, res = send_rpc(call_qb)
print(f"Status: {status}, Response: {res}")

time.sleep(3)

