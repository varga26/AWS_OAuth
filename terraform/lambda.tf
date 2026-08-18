locals {
  layer_dir = "${path.module}/../layer"
}

resource "null_resource" "build_layer" {
  triggers = { always_run = timestamp() }
  provisioner "local-exec" {
    command = <<EOT
      rm -rf ${local.layer_dir}
      mkdir -p ${local.layer_dir}/python
      pip3 install requests -t ${local.layer_dir}/python
    EOT
  }
}


data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/lambda.py"
  output_path = "${path.module}/../lambda/healthcheck.zip"
}

data "archive_file" "layer_zip" {
  type        = "zip"
  source_dir  = "${local.layer_dir}"
  output_path = "${path.module}/../lambda/layer.zip"
  depends_on = [null_resource.build_layer]
}

resource "aws_lambda_function" "healthcheck" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "healthcheck"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda.lambda_handler"
  runtime          = "python3.12"
  timeout          = 15

  layers = [aws_lambda_layer_version.python_dependencies_layer.arn]

  environment {
    variables = {
      URL_TO_CHECK   = var.url
      SNS_TOPIC_ARN  = aws_sns_topic.healthcheck.arn
      SSM_PARAM_NAME = "/monitor/state"
      PYTHONUNBUFFERED = "1"
    }
  }

}

resource "aws_lambda_layer_version" "python_dependencies_layer" {
  filename            = data.archive_file.layer_zip.output_path
  layer_name          = "python_dependencies_layer"
  compatible_runtimes = ["python3.12"]
  compatible_architectures = ["x86_64"]
}

resource "aws_iam_role" "lambda" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda-sns-policy" {
  name = "lambda-sns-policy"
  role = aws_iam_role.lambda.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.healthcheck.arn,
      },
      {
        Effect   = "Allow",
        Action   = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ],
        Resource = "arn:aws:ssm:*:*:parameter/monitor/state"
      },
      {
        Effect   = "Allow",
        Action   = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda-sns-policy" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_sns_topic" "healthcheck" {
  name = "healthcheck"
}

resource "aws_sns_topic_subscription" "healthcheck" {
  topic_arn = aws_sns_topic.healthcheck.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "healthcheck" {
  alarm_name          = "healthcheck-alarm"
  namespace           = "Custom/HealthCheck"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  period              = "300"
  threshold           = "0"
  treat_missing_data = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.healthcheck.function_name
  }
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.healthcheck.arn]
  ok_actions          = [aws_sns_topic.healthcheck.arn]
}

resource "aws_cloudwatch_metric_alarm" "healthcheck_escalation" {
  alarm_name          = "healthcheck-alarm-escalation"
  namespace           = "Custom/HealthCheck"
  metric_name         = "HealthCheckStatus"
  statistic           = "Maximum" 
  comparison_operator = "GreaterThanThreshold"
  threshold           = "0"
  period              = "300"
  evaluation_periods  = "9"   
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = aws_lambda_function.healthcheck.function_name
  }
  alarm_actions = [aws_sns_topic.healthcheck.arn]
}



resource "aws_cloudwatch_dashboard" "healthcheck_dashboard" {
  dashboard_name = "HealthCheck-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24 
        height = 6
        properties = {
          metrics = [
            ["Custom/HealthCheck", "HealthCheckStatus", "FunctionName", aws_lambda_function.healthcheck.function_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Maximum"
          period  = 300
          title   = "Health Check Status (0 = UP, 1 = DOWN)"
          yAxis = {
            left = {
              min = 0
              max = 1.5
            }
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "every_five_minutes" {
  name                = "_lambda-every-5-minutes"
  description         = "Fires every five minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.every_five_minutes.name
  target_id = "healthcheck-lambda"
  arn       = aws_lambda_function.healthcheck.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.healthcheck.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_five_minutes.arn
}