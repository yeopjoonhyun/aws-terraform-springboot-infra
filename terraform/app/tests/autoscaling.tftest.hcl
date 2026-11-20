mock_provider "aws" {}

override_data {
  target = data.terraform_remote_state.network
  values = {
    outputs = {
      vpc_id                     = "vpc-00000000"
      public_subnet_ids          = ["subnet-00000001", "subnet-00000002"]
      private_app_subnet_ids     = ["subnet-00000003", "subnet-00000004"]
      subnet_ids                 = { public-a = "subnet-00000001" }
      security_group_ids         = { alb = "sg-00000001", app = "sg-00000002" }
      private_app_route_table_id = "rtb-00000000"
    }
  }
}

override_data {
  target = data.terraform_remote_state.registry
  values = {
    outputs = {
      ecr_repository_url = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/aws-tf-springboot-app"
    }
  }
}

override_data {
  target = data.terraform_remote_state.data
  values = {
    outputs = {
      db_host       = "example.invalid"
      db_name       = "notes"
      db_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:123456789012:secret:example-AbCdEf"
    }
  }
}

variables {
  aws_account_id = "123456789012"
  image_tag      = "test"
}

run "ecs_service_cpu_target_tracking" {
  command = plan

  assert {
    condition = (
      aws_ecs_service.app.desired_count == aws_appautoscaling_target.app.min_capacity &&
      length(aws_ecs_service.app.network_configuration[0].subnets) == 2 &&
      aws_ecs_service.app.availability_zone_rebalancing == "ENABLED"
    )
    error_message = "The service must start at minimum capacity across two subnets with AZ rebalancing."
  }

  assert {
    condition = (
      aws_appautoscaling_target.app.resource_id == "service/aws-tf-springboot-cluster/aws-tf-springboot-app" &&
      aws_appautoscaling_target.app.scalable_dimension == "ecs:service:DesiredCount" &&
      aws_appautoscaling_target.app.min_capacity == 2 &&
      aws_appautoscaling_target.app.max_capacity == 4
    )
    error_message = "The scaling target must control this ECS service within the 2–4 task range."
  }

  assert {
    condition = (
      aws_appautoscaling_policy.cpu.resource_id == aws_appautoscaling_target.app.resource_id &&
      aws_appautoscaling_policy.cpu.policy_type == "TargetTrackingScaling" &&
      aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].target_value == 60 &&
      aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ECSServiceAverageCPUUtilization" &&
      !coalesce(aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].disable_scale_in, false)
    )
    error_message = "The policy must track ECS service CPU at 60% and allow scale-in."
  }
}
