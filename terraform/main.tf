locals {
  name = var.project

  # 필수 태그 (Policy as Code 로 검사)
  common_tags = {
    project = var.project
    owner   = var.owner
    managed = "terraform"
  }

  lb_nodes   = { for k, v in var.nodes : k => v if v.role == "lb" }
  app_nodes  = { for k, v in var.nodes : k => v if v.role == "app" }
  data_nodes = { for k, v in var.nodes : k => v if v.role == "data" }
  mon_nodes  = { for k, v in var.nodes : k => v if v.role == "mon" }

  # cloud-init 템플릿에 넘길 토폴로지 정보
  topology = {
    lb_ips   = [for v in values(local.lb_nodes) : v.ip]
    app_ips  = [for v in values(local.app_nodes) : v.ip]
    data_ip  = one([for v in values(local.data_nodes) : v.ip])
    mon_ip   = one([for v in values(local.mon_nodes) : v.ip])
    all_ips  = [for v in values(var.nodes) : v.ip]
    net_cidr = var.network_cidr
  }

  # 진입점 VM (entry_mode = port_forward 일 때 80/443 을 받는 lb)
  entry_lb = var.entry_lb

  # VM 에 내려보낼 파일 (경로 => 내용). Windows 에서 CRLF 로 저장돼도 서버에서 깨지지 않도록 LF 로 바꾼다.
  repo = "${path.module}/.."
  bootstrap_common = {
    "/opt/bootstrap/common.sh" = replace(file("${local.repo}/config/bootstrap/common.sh"), "\r\n", "\n")
  }
  bootstrap_role = {
    lb = {
      "/opt/bootstrap/lb.sh" = replace(file("${local.repo}/config/bootstrap/lb.sh"), "\r\n", "\n")
    }
    app = {
      "/opt/bootstrap/app.sh"               = replace(file("${local.repo}/config/bootstrap/app.sh"), "\r\n", "\n")
      "/opt/bootstrap/app/app.py"           = replace(file("${local.repo}/app/app.py"), "\r\n", "\n")
      "/opt/bootstrap/app/requirements.txt" = replace(file("${local.repo}/app/requirements.txt"), "\r\n", "\n")
      "/opt/bootstrap/app/att-app.service"  = replace(file("${local.repo}/app/att-app.service"), "\r\n", "\n")
    }
    data = {
      "/opt/bootstrap/data.sh" = replace(file("${local.repo}/config/bootstrap/data.sh"), "\r\n", "\n")
    }
    mon = {
      "/opt/bootstrap/mon.sh"                    = replace(file("${local.repo}/config/bootstrap/mon.sh"), "\r\n", "\n")
      "/opt/bootstrap/alerts.yml"                = replace(file("${local.repo}/config/prometheus/alerts.yml"), "\r\n", "\n")
      "/opt/bootstrap/grafana/att-overview.json" = replace(file("${local.repo}/config/grafana/att-overview.json"), "\r\n", "\n")
    }
  }
}

############################################
# 1) 격리 네트워크 (W1·W3·W7)
############################################
resource "cloudstack_network" "main" {
  name             = "${local.name}-net"
  display_text     = "${local.name} isolated network"
  cidr             = var.network_cidr
  network_offering = var.network_offering
  zone             = var.zone
  tags             = local.common_tags
}

# 아웃바운드: 패키지 설치·NTP·DNS 에 필요한 포트만 연다 (W1 "필요한 네 줄")
resource "cloudstack_egress_firewall" "main" {
  network_id = cloudstack_network.main.id

  depends_on = [cloudstack_instance.node]

  rule {
    cidr_list = [var.network_cidr]
    protocol  = "tcp"
    ports     = ["80", "443"]
  }

  rule {
    cidr_list = [var.network_cidr]
    protocol  = "udp"
    ports     = ["53", "123"]
  }
}

############################################
# 2) SSH 키
############################################
resource "cloudstack_ssh_keypair" "admin" {
  name       = "${local.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

############################################
# 3) VM
############################################
resource "cloudstack_instance" "node" {
  for_each = var.nodes

  name             = "${local.name}-${each.key}"
  display_name     = "${local.name}-${each.key}"
  service_offering = each.value.offering
  template         = var.template
  zone             = var.zone
  network_id       = cloudstack_network.main.id
  ip_address       = each.value.ip
  keypair          = cloudstack_ssh_keypair.admin.name
  expunge          = true

  # 설정은 config/bootstrap/*.sh 에 두고, cloud-init 은 파일 배치·실행만 한다.
  # (주의) 비밀번호가 user_data·tfstate 에 남는다 → tfstate 는 절대 커밋·제출 금지
  user_data = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    hostname       = each.key
    role           = each.value.role
    self_ip        = each.value.ip
    topology       = local.topology
    redis_password = var.redis_password
    db_password    = var.db_password
    files          = merge(local.bootstrap_common, local.bootstrap_role[each.value.role])
  })

  tags = merge(local.common_tags, { role = each.value.role, name = each.key })

  lifecycle {
    precondition {
      condition     = contains(var.allowed_offerings, each.value.offering)
      error_message = "허용되지 않은 오퍼링입니다: ${each.value.offering}"
    }
  }
}

resource "cloudstack_disk" "data" {
  for_each = { for k, v in var.nodes : k => v if v.disk_size > 0 }

  name               = "${local.name}-${each.key}-data"
  attach             = true
  disk_offering      = var.disk_offering
  size               = each.value.disk_size
  virtual_machine_id = cloudstack_instance.node[each.key].id
  zone               = var.zone
  tags               = local.common_tags
}

############################################
# 4) 공인 IP 두 개: 서비스용 / 관리용 분리
#    CloudStack 은 한 IP 를 LB 와 포트포워딩에 동시에 쓸 수 없고,
#    접근 경로 분리(②-네트워크)도 이렇게 드러난다.
############################################
resource "cloudstack_ipaddress" "service" {
  network_id = cloudstack_network.main.id
  zone       = var.zone
}

resource "cloudstack_ipaddress" "mgmt" {
  network_id = cloudstack_network.main.id
  zone       = var.zone
}

############################################
# 5) 서비스 진입점
#    entry_mode = "vr_lb"        : 가상 라우터 LB 규칙으로 lb01·lb02 에 분산 (Nginx SPOF 제거)
#    entry_mode = "port_forward" : 오퍼링에 LB 서비스가 없을 때. entry_lb 한 대로 포워딩
############################################
resource "cloudstack_loadbalancer_rule" "https" {
  count = var.entry_mode == "vr_lb" ? 1 : 0

  name          = "${local.name}-https"
  ip_address_id = cloudstack_ipaddress.service.id
  network_id    = cloudstack_network.main.id
  algorithm     = "roundrobin"
  protocol      = "tcp"
  public_port   = 443
  private_port  = 443
  member_ids    = [for k in keys(local.lb_nodes) : cloudstack_instance.node[k].id]
}

resource "cloudstack_loadbalancer_rule" "http" {
  count = var.entry_mode == "vr_lb" ? 1 : 0

  name          = "${local.name}-http"
  ip_address_id = cloudstack_ipaddress.service.id
  network_id    = cloudstack_network.main.id
  algorithm     = "roundrobin"
  protocol      = "tcp"
  public_port   = 80
  private_port  = 80
  member_ids    = [for k in keys(local.lb_nodes) : cloudstack_instance.node[k].id]
}

resource "cloudstack_port_forward" "service" {
  count = var.entry_mode == "port_forward" ? 1 : 0

  ip_address_id = cloudstack_ipaddress.service.id

  forward {
    protocol           = "tcp"
    private_port       = 80
    public_port        = 80
    virtual_machine_id = cloudstack_instance.node[local.entry_lb].id
  }

  forward {
    protocol           = "tcp"
    private_port       = 443
    public_port        = 443
    virtual_machine_id = cloudstack_instance.node[local.entry_lb].id
  }
}

resource "cloudstack_firewall" "service" {
  ip_address_id = cloudstack_ipaddress.service.id
  parallelism   = 1

  depends_on = [cloudstack_loadbalancer_rule.http, cloudstack_loadbalancer_rule.https, cloudstack_port_forward.service]

  rule {
    cidr_list = var.service_cidrs
    protocol  = "tcp"
    ports     = ["80", "443"]
  }
}

############################################
# 6) 관리 경로: VM 별 22xx → 22, 관측 UI (VPN 대역만)
############################################
resource "cloudstack_port_forward" "mgmt" {
  ip_address_id = cloudstack_ipaddress.mgmt.id

  dynamic "forward" {
    for_each = var.nodes
    content {
      protocol           = "tcp"
      private_port       = 22
      public_port        = forward.value.ssh_port
      virtual_machine_id = cloudstack_instance.node[forward.key].id
    }
  }

  # Grafana(3000) · Prometheus(9090) - mon 노드
  dynamic "forward" {
    for_each = local.mon_nodes
    content {
      protocol           = "tcp"
      private_port       = 3000
      public_port        = 3000
      virtual_machine_id = cloudstack_instance.node[forward.key].id
    }
  }

  dynamic "forward" {
    for_each = local.mon_nodes
    content {
      protocol           = "tcp"
      private_port       = 9090
      public_port        = 9090
      virtual_machine_id = cloudstack_instance.node[forward.key].id
    }
  }
}

resource "cloudstack_firewall" "mgmt" {
  ip_address_id = cloudstack_ipaddress.mgmt.id
  parallelism   = 1

  depends_on = [cloudstack_port_forward.mgmt]

  rule {
    cidr_list = var.admin_cidrs
    protocol  = "tcp"
    ports     = concat([for n in values(var.nodes) : tostring(n.ssh_port)], ["3000", "9090"])
  }
}
