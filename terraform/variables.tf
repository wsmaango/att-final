############################################
# 공통
############################################
variable "project" {
  description = "자원 이름 접두사 (예: att-학번). 다른 학생 자원과 겹치지 않게 학번을 넣는다."
  type        = string
}

variable "owner" {
  description = "필수 태그 owner 값 (학번)"
  type        = string
}

variable "zone" {
  description = "Solid Cloud Zone"
  type        = string
  default     = "DKU"
}

variable "template" {
  description = "VM 템플릿 이름 (콘솔 Images > Templates 에서 확인)"
  type        = string
  default     = "Ubuntu_24.04"
}

variable "network_offering" {
  description = "격리 네트워크 오퍼링 (W1: Source NAT·방화벽·포트포워딩·LB 포함)"
  type        = string
  default     = "DefaultIsolatedNetworkOfferingWithSourceNatService"
}

############################################
# 네트워크 (W1·W3·W7 격리 네트워크 관례를 그대로 사용)
############################################
variable "network_cidr" {
  description = "격리 네트워크 CIDR"
  type        = string
  default     = "192.168.0.0/24"
}

variable "admin_cidrs" {
  description = "SSH·관측 UI 접근을 허용할 출처 (VPN 대역). 0.0.0.0/0 금지 - 정책으로 검사"
  type        = list(string)
  default     = ["10.8.0.0/24"]

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs 에 0.0.0.0/0 을 넣을 수 없습니다."
  }
}

variable "service_cidrs" {
  description = "서비스(80/443) 접근 허용 출처. Solid Cloud는 교내망·VPN에서만 도달한다."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

############################################
# VM 구성. 역할별 대수·고정 IP·오퍼링을 한 곳에서 관리한다.
############################################
variable "allowed_offerings" {
  description = "허용 오퍼링 목록 (비용 상한 정책)"
  type        = list(string)
  default     = ["Small", "Medium"]
}

variable "nodes" {
  description = "역할별 VM 정의. key 가 VM 이름 뒤쪽이 된다."
  type = map(object({
    role      = string # lb | app | data | mon
    ip        = string # 격리 네트워크 안 고정 IP
    offering  = string # 서비스 오퍼링 이름
    ssh_port  = number # 관리용 공인 포트 (포트포워딩 → 22)
    disk_size = number # 추가 데이터 디스크(GB). 0 이면 만들지 않음
  }))

  default = {
    lb01   = { role = "lb", ip = "192.168.0.20", offering = "Medium", ssh_port = 2201, disk_size = 0 }
    lb02   = { role = "lb", ip = "192.168.0.21", offering = "Medium", ssh_port = 2202, disk_size = 0 }
    app01  = { role = "app", ip = "192.168.0.10", offering = "Medium", ssh_port = 2203, disk_size = 0 }
    app02  = { role = "app", ip = "192.168.0.11", offering = "Medium", ssh_port = 2204, disk_size = 0 }
    data01 = { role = "data", ip = "192.168.0.30", offering = "Medium", ssh_port = 2205, disk_size = 0 }
    mon01  = { role = "mon", ip = "192.168.0.40", offering = "Medium", ssh_port = 2206, disk_size = 0 }
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["lb", "app", "data", "mon"], n.role)])
    error_message = "role 은 lb, app, data, mon 중 하나여야 합니다."
  }
}

variable "disk_offering" {
  description = "추가 데이터 디스크 오퍼링 이름 (콘솔에서 확인, Custom 크기 지원 오퍼링)"
  type        = string
  default     = "Custom"
}

variable "ssh_public_key_path" {
  description = "VM 에 등록할 공개키 경로 (개인키가 아니라 .pub)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

############################################
# 애플리케이션 시크릿 - tfvars.example 에는 더미 값만
############################################
variable "redis_password" {
  description = "Redis requirepass (W5). 실제 값은 TF_VAR_redis_password 환경변수로 주입 권장"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9]{12,40}$", var.redis_password))
    error_message = "redis_password 는 영문·숫자 12~40자여야 합니다 (설정 파일 치환 안전성)."
  }
}

variable "db_password" {
  description = "PostgreSQL 앱 계정 비밀번호. TF_VAR_db_password 로 주입 권장"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9]{12,40}$", var.db_password))
    error_message = "db_password 는 영문·숫자 12~40자여야 합니다 (설정 파일 치환 안전성)."
  }
}

############################################
# 서비스 진입 방식 (설계 대안 비교용)
############################################
variable "entry_mode" {
  description = "vr_lb: 가상 라우터 LB 규칙으로 lb 전체에 분산 / port_forward: entry_lb 한 대로 포워딩"
  type        = string
  default     = "vr_lb"

  validation {
    condition     = contains(["vr_lb", "port_forward"], var.entry_mode)
    error_message = "entry_mode 는 vr_lb 또는 port_forward 입니다."
  }
}

variable "entry_lb" {
  description = "entry_mode = port_forward 일 때 80/443 을 받을 lb 노드 이름 (장애 시 lb02 로 바꿔 apply)"
  type        = string
  default     = "lb01"
}
