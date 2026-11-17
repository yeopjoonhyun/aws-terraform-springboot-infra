output "alb_url" {
  description = "앱 접속 주소"
  value       = "http://${aws_lb.app.dns_name}"
}
