terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudstack = {
      source = "cloudstack/cloudstack"
      # 0.5.0 고정: 0.6.0+ 는 LB 규칙 생성 후 오토스케일 그룹 조회 실패 시 nil 포인터 패닉
      # (Solid Cloud 학생 계정에서 재현, resource_cloudstack_loadbalancer_rule.go:274)
      version = "0.5.0"
    }
  }
}

# 자격 증명은 코드·tfvars에 넣지 않는다 (W7 Part D 시크릿 분리 원칙).
# 실행 전에 환경변수로 주입한다:
#   export CLOUDSTACK_API_URL="https://<콘솔 주소>/client/api"
#   export CLOUDSTACK_API_KEY="..."
#   export CLOUDSTACK_SECRET_KEY="..."
provider "cloudstack" {}
