# ALB: 인터넷 요청을 받아 건강한 앱 컨테이너로 나눠 보낸다. 퍼블릭 서브넷 2개(AZ 2개)에 걸쳐 있다.
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  security_groups    = [local.net.security_group_ids["alb"]]
  subnets            = local.net.public_subnet_ids
}

# 대상 그룹: ALB가 요청을 보낼 앱 컨테이너 목록. Fargate는 컨테이너마다 IP를 받으므로 target_type은 ip.
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.net.vpc_id

  # 컨테이너를 뺄 때 처리 중인 요청을 기다리는 시간. 기본 300초는 실습에서 destroy만 느리게 한다.
  deregistration_delay = 30

  # 이 경로가 200을 돌려줘야 "건강한" 컨테이너로 보고 요청을 보낸다
  health_check {
    path                = "/actuator/health"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ponytail: HTTP(80)만 연다. HTTPS(443)는 도메인과 인증서(ACM)가 생기면 추가한다.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
