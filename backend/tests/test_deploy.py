"""Checks of the deployment files (docker-compose.yml, .env.example) that can run without Docker."""

import ipaddress
import re

import pytest

from app.config import BACKEND_DIR

yaml = pytest.importorskip("yaml")


def compose() -> dict:
    return yaml.safe_load((BACKEND_DIR / "docker-compose.yml").read_text(encoding="utf-8"))


def compose_default(value: str) -> str:
    """The default in a compose value such as "${NAME:-default}"."""
    match = re.fullmatch(r"\$\{\w+:-([^}]*)\}", value)
    assert match, value
    return match.group(1)


def env_example_value(name: str) -> str:
    text = (BACKEND_DIR / ".env.example").read_text(encoding="utf-8")
    (value,) = re.findall(rf"^{name}=(.*)$", text, flags=re.MULTILINE)
    return value


def test_trusted_proxy_is_the_compose_gateway_not_localhost():
    """A reverse proxy on the host reaches the container from the network gateway, never from 127.0.0.1.

    Trusting 127.0.0.1 would make every visitor share the proxy's address, so 30 wrong passwords from
    anyone would lock everybody out of signing in.
    """
    (network,) = compose()["networks"]["default"]["ipam"]["config"]
    gateway = ipaddress.ip_address(network["gateway"])
    assert gateway in ipaddress.ip_network(network["subnet"])
    trusted = compose()["services"]["api"]["environment"]["FORWARDED_ALLOW_IPS"]
    assert compose_default(trusted) == str(gateway)
    assert env_example_value("FORWARDED_ALLOW_IPS") == str(gateway)  # `cp .env.example .env` must keep it right


def test_no_wildcard_trust_for_forwarded_headers():
    assert "*" not in env_example_value("FORWARDED_ALLOW_IPS")
    assert "*" not in compose()["services"]["api"]["environment"]["FORWARDED_ALLOW_IPS"]
