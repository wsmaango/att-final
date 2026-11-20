"""Checkov 사용자 정의 정책 (Policy as Code)

실행: checkov -d terraform --external-checks-dir terraform/policies
plan 검사: terraform show -json plan.out > plan.json && checkov -f plan.json --external-checks-dir terraform/policies
"""
from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

PUBLIC = {"0.0.0.0/0", "::/0"}
WEB_PORTS = {"80", "443"}
ALLOWED_OFFERINGS = {"Small", "Medium"}
REQUIRED_TAGS = {"project", "owner", "role"}


def _first(v):
    """HCL 파서는 값을 [value] 형태로 감싸는 경우가 많다."""
    while isinstance(v, list) and len(v) == 1:
        v = v[0]
    return v


def _as_list(v):
    v = _first(v)
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


class PublicOnlyWebPorts(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="ATT1: 0.0.0.0/0 에는 80·443 만 열 수 있다 (SSH·관측 포트 전체 공개 금지)",
            id="CKV_ATT_1",
            categories=[CheckCategories.NETWORKING],
            supported_resources=["cloudstack_firewall"],
        )

    def scan_resource_conf(self, conf):
        for rule in conf.get("rule", []):
            rule = _first(rule)
            cidrs = {str(c) for c in _as_list(rule.get("cidr_list"))}
            ports = {str(p) for p in _as_list(rule.get("ports"))}
            if cidrs & PUBLIC and (not ports or ports - WEB_PORTS):
                return CheckResult.FAILED
        return CheckResult.PASSED


class InstanceRequiredTags(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="ATT2: VM 에 project·owner·role 태그 필수",
            id="CKV_ATT_2",
            categories=[CheckCategories.CONVENTION],
            supported_resources=["cloudstack_instance"],
        )

    def scan_resource_conf(self, conf):
        tags = _first(conf.get("tags"))
        if isinstance(tags, str):
            # merge(local.common_tags, { role = ... }) 처럼 해석되지 않은 식이면 키 이름으로 확인
            return CheckResult.PASSED if all(t in tags for t in ("common_tags", "role")) else CheckResult.FAILED
        if not isinstance(tags, dict):
            return CheckResult.FAILED
        return CheckResult.PASSED if REQUIRED_TAGS <= set(tags) else CheckResult.FAILED


class InstanceOfferingCap(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="ATT3: VM 오퍼링은 Small·Medium 까지만 (비용 상한)",
            id="CKV_ATT_3",
            categories=[CheckCategories.CONVENTION],
            supported_resources=["cloudstack_instance"],
        )

    def scan_resource_conf(self, conf):
        off = str(_first(conf.get("service_offering")))
        if off in ALLOWED_OFFERINGS:
            return CheckResult.PASSED
        if "each.value" in off or "var." in off:
            # for_each 값은 정적으로 풀리지 않는다 → plan.json 검사와 variables.tf precondition 이 담당
            return CheckResult.UNKNOWN
        return CheckResult.FAILED


class EgressNotAllOpen(BaseResourceCheck):
    def __init__(self):
        super().__init__(
            name="ATT4: Egress 는 포트를 지정해야 한다 (protocol all 금지)",
            id="CKV_ATT_4",
            categories=[CheckCategories.NETWORKING],
            supported_resources=["cloudstack_egress_firewall"],
        )

    def scan_resource_conf(self, conf):
        for rule in conf.get("rule", []):
            rule = _first(rule)
            if str(_first(rule.get("protocol"))).lower() == "all" or not _as_list(rule.get("ports")):
                return CheckResult.FAILED
        return CheckResult.PASSED


check1 = PublicOnlyWebPorts()
check2 = InstanceRequiredTags()
check3 = InstanceOfferingCap()
check4 = EgressNotAllOpen()
