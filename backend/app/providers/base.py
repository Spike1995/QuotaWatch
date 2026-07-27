"""Provider adapter contract and normalized errors for stage 6.

本模块本身不发起请求。真实 Provider 必须有独立任务卡、用户明确授权、默认关闭的开关和
离线失败路径测试；Codex 本地 app-server、Kimi 官方 HTTPS 与 GLM 实验性 HTTPS Adapter
均已按各自任务卡实现。GLM 后续脱敏本机结构检查已由单独的用户风险决定授权。

设计依据：docs/STAGE6_PROVIDER_DESIGN.md、docs/API_RESEARCH.md 第零节。
"""

from __future__ import annotations

from typing import Protocol

from ..models import ProviderName, ProviderQuota


class ProviderError(Exception):
    """适配器抛出的归一化异常基类。聚合层捕获后转成结构化 ProviderQuota 错误。"""

    # 用户可读的中文文案，归一后写入 ProviderQuota.error_message。
    user_message: str = "查询失败"


class AuthError(ProviderError):
    """401/403：凭据缺失、过期或无权限。"""

    user_message = "需要重新登录或检查凭据"


class RateLimitError(ProviderError):
    """429：查询过于频繁或额度查询本身被限流。"""

    user_message = "查询过于频繁，请稍后重试"


class ContractError(ProviderError):
    """响应结构变化：字段缺失/类型不符，疑似服务商接口已变更。"""

    user_message = "服务商接口可能已变化"


class ProviderTimeoutError(ProviderError):
    """查询超时。"""

    user_message = "查询超时"


class ProviderConnectionError(ProviderError):
    """断网或无法连接到服务商。"""

    user_message = "无法连接到服务商"


class ProviderAdapter(Protocol):
    """每家 Provider 的只读额度查询适配器。

    实现类必须：
    - 返回归一化后的 ProviderQuota（不泄漏专有字段或原始敏感响应）；
    - 成功返回 status="ok"（部分窗口缺失可返回 "degraded"）；
    - 失败时抛上面定义的 ProviderError 子类，由聚合层统一处理；
    - 绝不打印、日志或返回原始敏感响应。
    """

    @property
    def provider(self) -> ProviderName:  # pragma: no cover - 协议占位
        ...

    def fetch(self) -> ProviderQuota:  # pragma: no cover - 协议占位
        ...
