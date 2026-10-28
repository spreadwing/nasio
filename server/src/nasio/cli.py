import sys
import argparse

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

from nasio.services.auth_service import auth_service, UserRole


def handle_token(args):
    action = args.token_action
    if action == "reset":
        new_token = auth_service.regenerate_master_token()
        print("\n" + "=" * 60)
        print(">> [Nasio] Master 安全 Token 重新生成成功！")
        print("=" * 60)
        print(f"新 Master Token: {new_token}")
        print("\n提示: 新 Token 已永久写入 data/auth.json。")
        print("请在客户端服务连接设置中更新此 Token，或在 Docker/MCP 客户端中使用。")
        print("=" * 60 + "\n")
    elif action == "get":
        token = auth_service.get_master_token()
        if token:
            print(f"当前生效 Master Token: {token}")
        else:
            print("当前未配置 Master Token (运行于内网免密模式)")
    else:
        print("未知的 token 子命令，请使用 reset 或 get")


def handle_user(args):
    action = args.user_action
    if action == "list":
        users = auth_service.list_users()
        print("\n" + "=" * 60)
        print(f">> [Nasio] 用户列表 (共 {len(users)} 人)")
        print("=" * 60)
        for u in users:
            print(f"- 用户名: {u['username']:<15} 角色: {u['role']:<10} ID: {u['id']}")
            if u.get("token"):
                print(f"  专属 Token: {u['token']}")
        print("=" * 60 + "\n")
    elif action == "add":
        try:
            role = UserRole.ADMIN if args.admin else UserRole.USER
            user = auth_service.create_user(args.username, args.password, role)
            print("\n" + "=" * 60)
            print(f">> 用户 '{user.username}' 创建成功！")
            print(f"- 角色: {user.role}")
            print(f"- 专属 Token: {user.token}")
            print("=" * 60 + "\n")
        except Exception as e:
            print(f"[ERROR] 创建失败: {e}", file=sys.stderr)
            sys.exit(1)
    elif action == "delete":
        user = auth_service.get_user_by_username(args.username)
        if not user:
            print(f"[ERROR] 用户 '{args.username}' 不存在", file=sys.stderr)
            sys.exit(1)
        auth_service.delete_user(user.id)
        print(f"[SUCCESS] 用户 '{args.username}' 已删除")


def main():
    parser = argparse.ArgumentParser(
        description="Nasio 容器管理与鉴权 CLI 命令行工具",
        prog="python -m nasio.cli"
    )
    subparsers = parser.add_subparsers(dest="command", help="可用命令组")

    # 1. token 命令
    token_parser = subparsers.add_parser("token", help="Master Token 管理")
    token_subparsers = token_parser.add_subparsers(dest="token_action", help="Token 操作")
    token_subparsers.add_parser("reset", help="重新生成 Master Token")
    token_subparsers.add_parser("get", help="查看当前 Master Token")

    # 2. user 命令
    user_parser = subparsers.add_parser("user", help="用户账号与权限管理")
    user_subparsers = user_parser.add_subparsers(dest="user_action", help="用户操作")
    user_subparsers.add_parser("list", help="查看所有用户")

    add_parser = user_subparsers.add_parser("add", help="创建新用户")
    add_parser.add_argument("--username", "-u", required=True, help="用户名")
    add_parser.add_argument("--password", "-p", required=True, help="密码 (不少于6位)")
    add_parser.add_argument("--admin", action="store_true", help="指定为管理员权限 (默认为普通用户)")

    del_parser = user_subparsers.add_parser("delete", help="删除用户")
    del_parser.add_argument("--username", "-u", required=True, help="要删除的用户名")

    args = parser.parse_args()
    if args.command == "token":
        handle_token(args)
    elif args.command == "user":
        handle_user(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
