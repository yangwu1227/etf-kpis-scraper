resource "aws_lambda_function" "lambda_function" {
  function_name = "${var.stack_name}_lambda_function"
  description   = "Lambda function triggered by EventBridge to run ECS Fargate task"
  runtime       = var.lambda_runtime
  role          = data.terraform_remote_state.iam.outputs.lambda_execution_role_arn
  handler       = var.lambda_handler
  architectures = [var.lambda_architecture]
  timeout       = var.lambda_timeout

  s3_bucket = var.lambda_code_s3_bucket
  s3_key    = var.lambda_code_s3_key

  tags = local.tags

  environment {
    variables = {
      ASSIGN_PUBLIC_IP    = var.assign_public_ip
      ECS_CLUSTER_NAME    = data.terraform_remote_state.ecs_fargate.outputs.ecs_fargate_cluster_name
      ECS_CONTAINER_NAME  = data.terraform_remote_state.ecs_fargate.outputs.ecs_fargate_container_name
      ECS_TASK_DEFINITION = data.terraform_remote_state.ecs_fargate.outputs.ecs_fargate_task_definition_family
      SECURITY_GROUP      = data.terraform_remote_state.vpc.outputs.security_group_id
      SUBNET_1            = data.terraform_remote_state.vpc.outputs.public_subnet_ids[0]
      SUBNET_2            = data.terraform_remote_state.vpc.outputs.public_subnet_ids[1]
      env                 = var.env
    }
  }
}


resource "aws_cloudwatch_event_rule" "eventbridge_rule" {
  name                = "${var.stack_name}_eventbridge_rule"
  description         = "EventBridge rule triggering the Lambda function on a schedule"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.eventbridge_rule.name
  target_id = "${var.stack_name}_lambda_function_target"
  arn       = aws_lambda_function.lambda_function.arn
}

resource "aws_lambda_permission" "eventbridge_permission" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eventbridge_rule.arn
}
