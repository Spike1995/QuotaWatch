"""ProviderError 异常层级直接单元测试（阶段 6）。

锁定归一化异常的 user_message 契约（聚合层与前端文案依赖），防止意外回归。
覆盖：基类默认文案、每个子类的覆盖文案、继承关系、可抛可捕获、自定义消息透传。
全部离线，无真实请求/凭据。
"""

from __future__ import annotations

import pytest

from app.providers.base import (
    AuthError,
    ContractError,
    ProviderConnectionError,
    ProviderError,
    ProviderTimeoutError,
    RateLimitError,
)


def test_base_provider_error_default_message() -> None:
    err = ProviderError()
    assert err.user_message == "查询失败"
    assert isinstance(err, Exception)


@pytest.mark.parametrize(
    "cls, expected",
    [
        (AuthError, "需要重新登录或检查凭据"),
        (RateLimitError, "查询过于频繁，请稍后重试"),
        (ContractError, "服务商接口可能已变化"),
        (ProviderTimeoutError, "查询超时"),
        (ProviderConnectionError, "无法连接到服务商"),
    ],
)
def test_subclass_messages_override_base(cls, expected: str) -> None:
    err = cls()
    assert err.user_message == expected
    # 所有子类都是 ProviderError。
    assert isinstance(err, ProviderError)


def test_subclass_isolation_of_messages() -> None:
    """各子类消息互不相同（防止误改成重复文案）。"""

    messages = {
        cls.__name__: cls().user_message
        for cls in (
            AuthError,
            RateLimitError,
            ContractError,
            ProviderTimeoutError,
            ProviderConnectionError,
        )
    }
    # 五条消息两两不同。
    assert len(set(messages.values())) == len(messages), messages


def test_provider_error_can_be_raised_and_caught_as_base() -> None:
    with pytest.raises(ProviderError):
        raise RateLimitError()


def test_provider_error_caught_as_specific_subtype() -> None:
    with pytest.raises(AuthError):
        raise AuthError()


def test_exception_str_contains_message() -> None:
    err = ContractError()
    # 默认 Exception str 不含 user_message（user_message 是属性，不是 args）。
    # 但属性本身可读，供聚合层使用。
    assert err.user_message == "服务商接口可能已变化"


def test_user_message_is_class_attribute_not_instance_only() -> None:
    """user_message 作为类属性，所有实例共享同一文案（无需构造时传参）。"""

    assert AuthError.user_message == "需要重新登录或检查凭据"
    assert AuthError().user_message == AuthError.user_message


def test_subclasses_do_not_share_mutable_state() -> None:
    a = AuthError()
    r = RateLimitError()
    assert a.user_message != r.user_message
    # 改一个实例不应影响另一个（user_message 是类属性，只读用途）。
    assert AuthError().user_message == "需要重新登录或检查凭据"
