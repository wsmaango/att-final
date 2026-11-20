# 일부러 정책을 어기는 코드. checkov 가 FAILED 를 내는지 확인용 (배포 대상 아님)
resource "cloudstack_firewall" "bad_ssh" {
  ip_address_id = "dummy"
  rule {
    cidr_list = ["0.0.0.0/0"]
    protocol  = "tcp"
    ports     = ["22", "443"]
  }
}

resource "cloudstack_instance" "bad_vm" {
  name             = "bad"
  service_offering = "XLarge"
  template         = "Ubuntu_24.04"
  zone             = "DKU"
  tags             = { project = "x" }
}

resource "cloudstack_egress_firewall" "bad_egress" {
  network_id = "dummy"
  rule {
    cidr_list = ["192.168.0.0/24"]
    protocol  = "all"
  }
}
