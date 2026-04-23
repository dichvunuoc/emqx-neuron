from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .agent_runner import AgentRunner
from .models import (
    ConnectionActionResponse,
    ConnectionProfile,
    ConnectionProfileSaveRequest,
    ConnectionSaveResponse,
    ConnectionRuntimeStatus,
    ConnectionTestRequest,
    ConnectionTestResult,
    ErrorResponse,
)
from .service import RemoteControlService
from .store import ConnectionStore


def create_app() -> FastAPI:
    app = FastAPI(title="Neuron Remote Bootstrap Stub", version="0.1.0")

    profile_path = Path(
        os.environ.get(
            "REMOTE_PROFILE_PATH",
            "scripts/neuron-remote-control/backend-stub/data/connection-profile.json",
        )
    )
    schema_path = Path(
        os.environ.get(
            "REMOTE_CONNECTION_SCHEMA",
            "scripts/neuron-remote-control/contracts/connection-profile.schema.json",
        )
    )

    store = ConnectionStore(profile_path)
    runner = AgentRunner()
    service = RemoteControlService(store=store, runner=runner, schema_path=schema_path)

    @app.get("/api/v2/remote/connection", response_model=ConnectionProfile)
    def get_connection_profile() -> ConnectionProfile:
        return ConnectionProfile(**service.get_profile())

    @app.put("/api/v2/remote/connection", response_model=ConnectionSaveResponse)
    def save_connection_profile(payload: ConnectionProfileSaveRequest) -> ConnectionSaveResponse:
        try:
            saved = service.save_profile(payload.model_dump())
            return ConnectionSaveResponse(error=0, updatedAt=saved["updatedAt"])
        except ValueError as exc:
            raise HTTPException(status_code=400, detail={"errorCode": "INVALID_CONFIG", "message": str(exc)}) from exc

    @app.post("/api/v2/remote/connection/test", response_model=ConnectionTestResult)
    def test_connection(payload: ConnectionTestRequest) -> ConnectionTestResult:
        result = service.test_connection(payload.model_dump())
        return ConnectionTestResult(**result)

    @app.post("/api/v2/remote/connection/connect", response_model=ConnectionActionResponse)
    def connect() -> ConnectionActionResponse:
        result = service.connect()
        if result["error"] != 0:
            raise HTTPException(status_code=400, detail={"errorCode": "CONNECT_FAILED", "message": result["message"]})
        return ConnectionActionResponse(**result)

    @app.post("/api/v2/remote/connection/disconnect", response_model=ConnectionActionResponse)
    def disconnect() -> ConnectionActionResponse:
        result = service.disconnect()
        return ConnectionActionResponse(**result)

    @app.get("/api/v2/remote/connection/status", response_model=ConnectionRuntimeStatus)
    def status() -> ConnectionRuntimeStatus:
        return ConnectionRuntimeStatus(**service.status())

    @app.exception_handler(HTTPException)
    async def http_exception_handler(_, exc: HTTPException):
        if isinstance(exc.detail, dict) and "errorCode" in exc.detail:
            return JSONResponse(status_code=exc.status_code, content=exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content=ErrorResponse(errorCode="HTTP_ERROR", message=str(exc.detail)).model_dump(),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(_, exc: RequestValidationError):
        first = exc.errors()[0] if exc.errors() else {}
        msg = first.get("msg", "request validation failed")
        return JSONResponse(
            status_code=400,
            content=ErrorResponse(errorCode="INVALID_REQUEST", message=msg).model_dump(),
        )

    return app


app = create_app()
