from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class ErrorResponse(BaseModel):
    errorCode: str
    message: str


class ConnectionProfile(BaseModel):
    enabled: bool = False
    gatewayId: str = Field(min_length=3, max_length=128)
    controlServerUrl: str
    authMode: Literal["mtls", "mtls_hmac"] = "mtls"
    hmacEnabled: bool = False
    heartbeatSec: int = Field(default=20, ge=5, le=120)
    reconnectSec: int = Field(default=3, ge=1, le=60)
    dryRunDefault: bool = True
    updatedAt: datetime


class ConnectionProfileSaveRequest(BaseModel):
    gatewayId: str = Field(min_length=3, max_length=128)
    controlServerUrl: str
    authMode: Literal["mtls", "mtls_hmac"] = "mtls"
    hmacSecret: Optional[str] = None
    heartbeatSec: int = Field(ge=5, le=120)
    reconnectSec: int = Field(ge=1, le=60)
    dryRunDefault: bool = True


class ConnectionSaveResponse(BaseModel):
    error: int = 0
    updatedAt: datetime


class ConnectionTestRequest(BaseModel):
    gatewayId: str = Field(min_length=3, max_length=128)
    controlServerUrl: str
    authMode: Literal["mtls", "mtls_hmac"] = "mtls"
    hmacSecret: Optional[str] = None


class ConnectionTestResult(BaseModel):
    ok: bool
    code: Literal[
        "CONNECTED",
        "TLS_FAILED",
        "AUTH_FAILED",
        "TIMEOUT",
        "ROUTER_NO_ACK",
        "INVALID_CONFIG",
    ]
    message: str
    latencyMs: Optional[int] = None
    checkedAt: datetime


class ConnectionRuntimeStatus(BaseModel):
    state: Literal["disabled", "connecting", "connected", "degraded", "disconnected"]
    lastError: Optional[str] = None
    lastHeartbeatAt: Optional[datetime] = None
    lastChangeAt: datetime


class ConnectionActionResponse(BaseModel):
    error: int = 0
    status: Literal["connecting", "connected", "failed", "disconnected"]
    message: str
