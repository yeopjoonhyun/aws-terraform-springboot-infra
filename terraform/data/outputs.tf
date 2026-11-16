# app 루트가 terraform_remote_state로 이 값들을 읽는다. 이름을 바꾸면 app도 고쳐야 한다.

output "db_host" {
  description = "RDS 접속 주소 (포트 제외)"
  value       = aws_db_instance.main.address
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "db_secret_arn" {
  description = "RDS가 만든 비밀(사용자 이름, 암호)의 ARN. 값이 아니라 위치라서 공개돼도 괜찮다."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}
