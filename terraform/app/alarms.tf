resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  alarm_description   = "ALB 자체에서 발생한 5xx가 최근 3분 중 2분 이상 분당 5건 이상"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching" # ALB는 오류가 0건일 때 이 지표를 보내지 않는다.

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "target_latency" {
  alarm_name                            = "${var.project_name}-target-latency"
  alarm_description                     = "앱 응답 시간 p95가 최근 3분 중 2분 이상 1초 초과"
  namespace                             = "AWS/ApplicationELB"
  metric_name                           = "TargetResponseTime"
  extended_statistic                    = "p95"
  comparison_operator                   = "GreaterThanThreshold"
  threshold                             = 1
  period                                = 60
  evaluation_periods                    = 3
  datapoints_to_alarm                   = 2
  treat_missing_data                    = "notBreaching"
  evaluate_low_sample_count_percentiles = "ignore"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}
