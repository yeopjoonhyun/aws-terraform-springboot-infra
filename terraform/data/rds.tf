# RDS가 들어갈 서브넷 묶음. network 루트의 DB 전용 프라이빗 서브넷 2개(2 AZ)를 쓴다.
# RDS는 지금 1개 AZ에만 뜨지만, 서브넷 그룹은 AWS 규칙상 2개 AZ 이상이어야 한다.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db"
  subnet_ids = [local.net.subnet_ids["db-a"], local.net.subnet_ids["db-b"]]
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-mysql"
  engine         = "mysql"
  engine_version = "8.4"
  instance_class = "db.t4g.micro" # 가장 작은 사양 (ARM, 시드니 시간당 $0.025)

  allocated_storage = 20 # GB (gp3 최소)
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "notes"
  username = "notesadmin"
  # 암호는 RDS가 직접 만들어 Secrets Manager에 넣는다. Terraform 코드와 state에 암호가 남지 않는다.
  # ponytail: RDS가 7일마다 암호를 자동 교체한다. 앱은 시작할 때만 암호를 받으므로,
  # 오래 켜 두게 되면 교체 후 작업을 재시작해야 한다 (실습은 1시간 안에 끝나서 해당 없음).
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [local.net.security_group_ids["db"]] # 앱 보안 그룹에서 3306만 허용
  publicly_accessible    = false
  multi_az               = false # 8단계(고가용성)에서 켠다. 켜면 요금이 2배.

  backup_retention_period = 7 # 자동 백업 7일 보관 (DB 크기만큼은 무료)

  # 실수로 지우지 않게 막는 장치. 끄려면 먼저 -var deletion_protection=false 로 apply한다.
  deletion_protection = var.deletion_protection

  # 지울 때 마지막 상태를 스냅샷으로 남긴다. 스냅샷은 보관 요금이 나가므로 실습 후 직접 지운다.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-mysql-final"
}
