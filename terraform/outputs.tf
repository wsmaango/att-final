output "service_ip" {
  description = "서비스 공인 IP (https://<이 값>/)"
  value       = cloudstack_ipaddress.service.ip_address
}

output "mgmt_ip" {
  description = "관리용 공인 IP (SSH 포트포워딩·Grafana·Prometheus)"
  value       = cloudstack_ipaddress.mgmt.ip_address
}

output "ssh_commands" {
  description = "VM 별 SSH 접속 명령 (VPN 연결 상태에서)"
  value       = { for k, v in var.nodes : k => "ssh -p ${v.ssh_port} ubuntu@${cloudstack_ipaddress.mgmt.ip_address}" }
}

output "private_ips" {
  description = "역할별 사설 IP"
  value       = { for k, v in var.nodes : k => "${v.role} ${v.ip}" }
}

output "dashboards" {
  value = {
    grafana    = "http://${cloudstack_ipaddress.mgmt.ip_address}:3000"
    prometheus = "http://${cloudstack_ipaddress.mgmt.ip_address}:9090"
  }
}

output "entry_mode" {
  value = var.entry_mode
}
