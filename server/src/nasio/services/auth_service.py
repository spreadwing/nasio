import os
import json
import uuid
import secrets
import hashlib
import logging
from typing import List, Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field

logger = logging.getLogger("nasio.auth")

def _detect_data_dir() -> str:
    env_dir = os.environ.get("DATA_DIR")
    if env_dir:
        return env_dir
    if os.path.exists("/app/data"):
        return "/app/data"
    curr = os.path.abspath(os.path.dirname(__file__))
    while curr and curr != os.path.dirname(curr):
        candidate = os.path.join(curr, "data")
        if os.path.exists(candidate) and os.path.isdir(candidate):
            return candidate
        curr = os.path.dirname(curr)
    return os.path.join(os.getcwd(), "data")

DATA_DIR = _detect_data_dir()
AUTH_PATH = os.environ.get("AUTH_PATH", os.path.join(DATA_DIR, "auth.json"))
USERS_PATH = os.environ.get("USERS_PATH", os.path.join(DATA_DIR, "users.json"))


class UserRole:
    ADMIN = "ADMIN"
    USER = "USER"


class UserModel(BaseModel):
    id: str = Field(default_factory=lambda: f"u_{uuid.uuid4().hex[:12]}")
    username: str
    password_hash: str
    salt: str
    role: str = UserRole.USER
    token: Optional[str] = None
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())

    def to_safe_dict(self) -> Dict[str, Any]:
        """脱敏输出，不包含密码哈希与 salt"""
        return {
            "id": self.id,
            "username": self.username,
            "role": self.role,
            "token": self.token,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class AuthUser(BaseModel):
    """当前鉴权成功的用户上下文信息"""
    id: str
    username: str
    role: str
    is_master: bool = False

    @property
    def is_admin(self) -> bool:
        return self.role == UserRole.ADMIN or self.is_master


class AuthService:
    _instance: Optional["AuthService"] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._init()
        return cls._instance

    def _init(self):
        os.makedirs(DATA_DIR, exist_ok=True)
        self._master_token: Optional[str] = None
        self._load_master_token()
        self._users: Dict[str, UserModel] = {}
        self._load_users()

    # -------------------------------------------------------------
    # 1. Master Token 管理
    # -------------------------------------------------------------
    def _load_master_token(self):
        if os.path.exists(AUTH_PATH):
            try:
                with open(AUTH_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    token = data.get("master_token")
                    if token and isinstance(token, str) and token.strip():
                        self._master_token = token.strip()
                        logger.info("Master Token loaded from %s", AUTH_PATH)
            except Exception as e:
                logger.error("Failed to load %s: %s", AUTH_PATH, e)

    def get_master_token(self) -> str:
        """获取生效的 Master Token，优先读取持久化配置，若无则使用环境变量"""
        if self._master_token:
            return self._master_token
        env_token = os.environ.get("MCP_AUTH_TOKEN", "").strip()
        return env_token

    def regenerate_master_token(self) -> str:
        """重新生成 Master Token 并持久化保存"""
        new_token = secrets.token_hex(24)
        self._master_token = new_token
        try:
            os.makedirs(os.path.dirname(AUTH_PATH), exist_ok=True)
            with open(AUTH_PATH, "w", encoding="utf-8") as f:
                json.dump({
                    "master_token": new_token,
                    "updated_at": datetime.utcnow().isoformat()
                }, f, indent=2, ensure_ascii=False)
            logger.info("New Master Token generated and saved to %s", AUTH_PATH)
        except Exception as e:
            logger.error("Failed to save master token to %s: %s", AUTH_PATH, e)
        return new_token

    # -------------------------------------------------------------
    # 2. 用户持久化与 CRUD
    # -------------------------------------------------------------
    def _load_users(self):
        self._users = {}
        if os.path.exists(USERS_PATH):
            try:
                with open(USERS_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        for item in data:
                            user = UserModel(**item)
                            self._users[user.id] = user
                logger.info("Loaded %d users from %s", len(self._users), USERS_PATH)
            except Exception as e:
                logger.error("Failed to load %s: %s", USERS_PATH, e)

    def _save_users(self):
        try:
            os.makedirs(os.path.dirname(USERS_PATH), exist_ok=True)
            with open(USERS_PATH, "w", encoding="utf-8") as f:
                data = [u.model_dump() for u in self._users.values()]
                json.dump(data, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error("Failed to save %s: %s", USERS_PATH, e)

    @staticmethod
    def hash_password(password: str, salt: str) -> str:
        return hashlib.sha256((password + salt).encode("utf-8")).hexdigest()

    def list_users(self) -> List[Dict[str, Any]]:
        return [u.to_safe_dict() for u in self._users.values()]

    def get_user_by_id(self, user_id: str) -> Optional[UserModel]:
        return self._users.get(user_id)

    def get_user_by_username(self, username: str) -> Optional[UserModel]:
        for u in self._users.values():
            if u.username.lower() == username.strip().lower():
                return u
        return None

    def create_user(self, username: str, password: str, role: str = UserRole.USER) -> UserModel:
        username = username.strip()
        if not username:
            raise ValueError("用户名不能为空")
        if not password or len(password) < 6:
            raise ValueError("密码长度不能少于 6 位")
        if self.get_user_by_username(username):
            raise ValueError(f"用户名 '{username}' 已存在")
        if role not in [UserRole.ADMIN, UserRole.USER]:
            role = UserRole.USER

        salt = secrets.token_hex(16)
        password_hash = self.hash_password(password, salt)
        user_token = f"u_tok_{secrets.token_hex(20)}"
        user = UserModel(
            username=username,
            password_hash=password_hash,
            salt=salt,
            role=role,
            token=user_token,
        )
        self._users[user.id] = user
        self._save_users()
        logger.info("User created: %s (role: %s)", username, role)
        return user

    def update_user(
        self,
        user_id: str,
        password: Optional[str] = None,
        role: Optional[str] = None
    ) -> UserModel:
        user = self.get_user_by_id(user_id)
        if not user:
            raise ValueError(f"用户不存在: {user_id}")

        if password is not None:
            if len(password) < 6:
                raise ValueError("密码长度不能少于 6 位")
            salt = secrets.token_hex(16)
            user.salt = salt
            user.password_hash = self.hash_password(password, salt)

        if role is not None and role in [UserRole.ADMIN, UserRole.USER]:
            user.role = role

        user.updated_at = datetime.utcnow().isoformat()
        self._users[user.id] = user
        self._save_users()
        logger.info("User updated: %s", user.username)
        return user

    def delete_user(self, user_id: str) -> bool:
        if user_id in self._users:
            username = self._users[user_id].username
            del self._users[user_id]
            self._save_users()
            logger.info("User deleted: %s", username)
            return True
        return False

    def regenerate_user_token(self, user_id: str) -> str:
        """重新生成指定用户的访问 Token 并持久化保存"""
        user = self.get_user_by_id(user_id)
        if not user:
            raise ValueError(f"用户不存在: {user_id}")
        new_token = f"u_tok_{secrets.token_hex(20)}"
        user.token = new_token
        user.updated_at = datetime.utcnow().isoformat()
        self._users[user.id] = user
        self._save_users()
        logger.info("User token regenerated: %s (%s)", user.username, user.id)
        return new_token

    # -------------------------------------------------------------
    # 3. 身份验证核心逻辑
    # -------------------------------------------------------------
    def verify_password(self, username: str, password: str) -> Optional[UserModel]:
        user = self.get_user_by_username(username)
        if not user:
            return None
        computed = self.hash_password(password, user.salt)
        if secrets.compare_digest(computed, user.password_hash):
            return user
        return None

    def authenticate_token(self, token: str) -> Optional[AuthUser]:
        clean_token = token.strip()
        if not clean_token:
            return None

        # 1. 匹配 Master Token
        master = self.get_master_token()
        if master and secrets.compare_digest(clean_token, master):
            return AuthUser(
                id="master",
                username="Master",
                role=UserRole.ADMIN,
                is_master=True,
            )

        # 2. 匹配具体用户 Token
        for u in self._users.values():
            if u.token and secrets.compare_digest(clean_token, u.token):
                return AuthUser(
                    id=u.id,
                    username=u.username,
                    role=u.role,
                    is_master=False,
                )

        return None

    def authenticate_basic(self, username: str, password: str) -> Optional[AuthUser]:
        # 兼容: 如果用户名是 master 或 admin 且密码直接匹配 Master Token
        master = self.get_master_token()
        if master and (username.lower() in ["master", "admin"]) and secrets.compare_digest(password, master):
            return AuthUser(
                id="master",
                username="Master",
                role=UserRole.ADMIN,
                is_master=True,
            )

        user = self.verify_password(username, password)
        if user:
            return AuthUser(
                id=user.id,
                username=user.username,
                role=user.role,
                is_master=False,
            )
        return None


auth_service = AuthService()
