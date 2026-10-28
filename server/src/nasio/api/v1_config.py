from typing import Dict, Any, List
from fastapi import APIRouter, Depends
from nasio.core.security import verify_auth_token, require_admin
from nasio.services.config_service import ConfigService

router = APIRouter(prefix="/config", tags=["Configuration"])


def _mask_config_secrets(cfg: Dict[str, Any]) -> Dict[str, Any]:
    if "downloaders" in cfg and "qbittorrent" in cfg["downloaders"]:
        if cfg["downloaders"]["qbittorrent"].get("password"):
            cfg["downloaders"]["qbittorrent"]["password"] = "******"
    if "downloaders" in cfg and "aria2" in cfg["downloaders"]:
        if cfg["downloaders"]["aria2"].get("rpc_secret"):
            cfg["downloaders"]["aria2"]["rpc_secret"] = "******"
    if "llm" in cfg and isinstance(cfg["llm"], dict):
        has_key = bool(cfg["llm"].get("api_key", "").strip())
        cfg["llm"]["has_api_key"] = has_key
        if has_key:
            cfg["llm"]["api_key"] = "******"
    if "webhook" in cfg and isinstance(cfg["webhook"], dict):
        has_secret = bool(cfg["webhook"].get("secret", "").strip())
        cfg["webhook"]["has_secret"] = has_secret
        if has_secret:
            cfg["webhook"]["secret"] = "******"
    return cfg


@router.get("", dependencies=[Depends(verify_auth_token)])
async def get_config() -> Dict[str, Any]:
    """获取当前脱敏后的系统配置及存储池状态"""
    cfg = _mask_config_secrets(ConfigService.get_config().model_dump())
    pools = ConfigService.get_storage_pools_status()
    return {"config": cfg, "storage_pools": pools}


@router.put("", dependencies=[Depends(require_admin)])
async def update_config(payload: Dict[str, Any]) -> Dict[str, Any]:
    """更新业务配置并热保存到 config.yaml (限管理员)"""
    updated = ConfigService.update_config(payload)
    return {
        "success": True,
        "message": "Configuration updated and reloaded",
        "config": _mask_config_secrets(updated.model_dump()),
    }


@router.post("/whitelist/add", dependencies=[Depends(require_admin)])
async def add_whitelist_path(payload: Dict[str, str]) -> Dict[str, Any]:
    """添加目录到白名单 (限管理员)"""
    path = payload.get("path", "").strip()
    if not path:
        return {"success": False, "error": "Path cannot be empty"}
    added = ConfigService.add_allowed_path(path)
    return {"success": added, "path": path}


@router.post("/whitelist/remove", dependencies=[Depends(require_admin)])
async def remove_whitelist_path(payload: Dict[str, str]) -> Dict[str, Any]:
    """从白名单移除目录 (限管理员)"""
    path = payload.get("path", "").strip()
    removed = ConfigService.remove_allowed_path(path)
    return {"success": removed, "path": path}
