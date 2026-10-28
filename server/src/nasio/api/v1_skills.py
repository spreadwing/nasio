from typing import List, Optional
from fastapi import APIRouter, HTTPException, Query, status
from pydantic import BaseModel, Field
from nasio.services.skill_service import skill_service

router = APIRouter(prefix="/skills", tags=["Skills"])


class SkillSummaryResponse(BaseModel):
    name: str
    description: str
    tags: List[str] = Field(default_factory=list)
    version: str = "1.0.0"
    updated_at: str
    file_size: int


class SkillDetailResponse(BaseModel):
    name: str
    description: str
    tags: List[str] = Field(default_factory=list)
    version: str = "1.0.0"
    updated_at: str
    file_size: int
    content: str
    body: str


class SkillSaveRequest(BaseModel):
    name: str = Field(..., description="技能英文标识名，如 anime_nas_workflow")
    description: str = Field(..., description="技能描述与触发条件")
    content: str = Field(..., description="技能 Markdown 完整内容")
    tags: Optional[List[str]] = Field(default_factory=list, description="分类标签")
    version: Optional[str] = Field(default="1.0.0", description="版本号")


@router.get("", response_model=List[SkillSummaryResponse], summary="获取服务端所有已持久化技能列表")
async def list_skills(
    keyword: Optional[str] = Query(None, description="搜索关键词（匹配名称、描述或标签）")
):
    skills = skill_service.list_skills()
    if keyword:
        kw = keyword.strip().lower()
        skills = [
            s for s in skills
            if kw in s["name"].lower()
            or kw in s["description"].lower()
            or any(kw in str(t).lower() for t in s.get("tags", []))
        ]
    return skills


@router.get("/{name}", response_model=SkillDetailResponse, summary="获取指定技能完整内容与元数据")
async def get_skill(name: str):
    skill = skill_service.get_skill(name)
    if not skill:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"技能 '{name}' 不存在",
        )
    return skill


@router.post("", response_model=SkillDetailResponse, summary="向服务端注册或更新技能")
async def save_skill(req: SkillSaveRequest):
    try:
        saved = skill_service.save_or_update_skill(
            name=req.name,
            description=req.description,
            content=req.content,
            tags=req.tags,
            version=req.version or "1.0.0",
        )
        return saved
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"保存技能失败: {str(e)}",
        )


@router.delete("/{name}", summary="删除指定技能")
async def delete_skill(name: str):
    success = skill_service.delete_skill(name)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"技能 '{name}' 不存在或删除失败",
        )
    return {"name": name, "deleted": True}
