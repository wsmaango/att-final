# CloudStack 전용 tflint 룰셋은 없으므로 terraform 기본 룰셋(recommended)만 사용
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
