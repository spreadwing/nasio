from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, Query, HTTPException, status
from nasio.core.security import verify_auth_token
from nasio.services.missing_mcp_service import missing_mcp_service, MissingMcpToolModel

router = APIRouter(prefix="/missing-mcp-tools", tags=["Missing MCP Tools"])


class ReportMissingToolRequest(BaseModel):
    tool_name: str
    description: str
    suggested_parameters: Optional[str] = None
    scenario: Optional[str] = None
    agent_task_id: Optional[str] = None


@router.get("", dependencies=[Depends(verify_auth_token)], response_model=List[MissingMcpToolModel])
async def list_missing_mcp_tools(limit: int = Query(100, ge=1, le=300)) -> List[MissingMcpToolModel]:
    """获取所有智能体上报的缺失 MCP 工具诉求记录"""
    return missing_mcp_service.list_missing_tools(limit=limit)


@router.post("", dependencies=[Depends(verify_auth_token)], response_model=MissingMcpToolModel)
async def report_missing_mcp_tool(req: ReportMissingToolRequest) -> MissingMcpToolModel:
    """上报缺失的 MCP 工具诉求"""
    return missing_mcp_service.report_missing_tool(
        tool_name=req.tool_name,
        description=req.description,
        suggested_parameters=req.suggested_parameters,
        scenario=req.scenario,
        agent_task_id=req.agent_task_id,
    )


@router.delete("/{req_id}", dependencies=[Depends(verify_auth_token)])
async def delete_missing_mcp_tool(req_id: str) -> Dict[str, Any]:
    """删除指定的缺失 MCP 工具上报记录"""
    success = missing_mcp_service.delete_missing_tool(req_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Reported missing MCP tool '{req_id}' not found",
        )
    return {"id": req_id, "deleted": True}


@router.delete("", dependencies=[Depends(verify_auth_token)])
async def clear_all_missing_mcp_tools() -> Dict[str, Any]:
    """清空所有缺失 MCP 工具上报记录"""
    cleared_count = missing_mcp_service.clear_all()
    return {"cleared_count": cleared_count}
