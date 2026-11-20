# Solid Cloud API 키 없이 CI 에서 도는 정책 테스트 (Terraform >= 1.7, mock provider)
# 실행: cd terraform && terraform init && terraform test

mock_provider "cloudstack" {}

variables {
  project             = "att-test"
  owner               = "00000000"
  ssh_public_key_path = "tests/fixtures/dummy.pub"
  redis_password      = "TestOnlyRedis123"
  db_password         = "TestOnlyDbPass123"
}

run "network_rules_follow_policy" {
  command = plan

  assert {
    condition     = alltrue([for r in cloudstack_firewall.mgmt.rule : !contains(r.cidr_list, "0.0.0.0/0")])
    error_message = "관리 경로(SSH·관측)는 0.0.0.0/0 에 열 수 없습니다."
  }

  assert {
    condition     = alltrue([for r in cloudstack_firewall.service.rule : length(setsubtract(r.ports, ["80", "443"])) == 0])
    error_message = "서비스 IP 에는 80·443 만 열 수 있습니다."
  }

  assert {
    condition     = alltrue([for r in cloudstack_egress_firewall.main.rule : r.protocol != "all" && length(r.ports) > 0])
    error_message = "Egress 는 프로토콜·포트를 지정해야 합니다."
  }

  assert {
    condition     = length([for v in values(var.nodes) : v if v.role == "lb"]) >= 2 && length([for v in values(var.nodes) : v if v.role == "app"]) >= 2
    error_message = "lb·app 는 각각 2대 이상이어야 합니다 (이중화)."
  }
}

run "rejects_ssh_open_to_world" {
  command = plan

  variables {
    admin_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.admin_cidrs]
}

run "rejects_oversized_offering" {
  command = plan

  variables {
    nodes = {
      lb01   = { role = "lb", ip = "192.168.0.20", offering = "Medium", ssh_port = 2201, disk_size = 0 }
      lb02   = { role = "lb", ip = "192.168.0.21", offering = "Medium", ssh_port = 2202, disk_size = 0 }
      app01  = { role = "app", ip = "192.168.0.10", offering = "Large", ssh_port = 2203, disk_size = 0 }
      app02  = { role = "app", ip = "192.168.0.11", offering = "Medium", ssh_port = 2204, disk_size = 0 }
      data01 = { role = "data", ip = "192.168.0.30", offering = "Medium", ssh_port = 2205, disk_size = 0 }
      mon01  = { role = "mon", ip = "192.168.0.40", offering = "Medium", ssh_port = 2206, disk_size = 0 }
    }
  }

  expect_failures = [cloudstack_instance.node["app01"]]
}
