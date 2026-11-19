resource "aws_appautoscaling_target" "app" {
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  min_capacity       = 2
  max_capacity       = 4
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-ecs-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_out_cooldown = 120 # 새 작업이 기동하고 CPU 지표에 반영될 시간을 준다.
    scale_in_cooldown  = 180

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
