terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudstack = {
      source  = "cloudstack/cloudstack"
      version = "~> 0.5"
    }
  }
}

# 자격 증명은 코드·tfvars에 넣지 않는다 (W7 Part D 시크릿 분리 원칙).
# 실행 전에 환경변수로 주입한다:
#   export CLOUDSTACK_API_URL="https://<콘솔 주소>/client/api"
#   export CLOUDSTACK_API_KEY="..."
#   export CLOUDSTACK_SECRET_KEY="..."
provider "cloudstack" {}
