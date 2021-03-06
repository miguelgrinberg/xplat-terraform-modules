# IAM
# Base AssumeRole policy for Lambda execution.
data "aws_iam_policy_document" "execution_lambda_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "Service"

      identifiers = [
        "lambda.amazonaws.com",
        "apigateway.amazonaws.com",
      ]
    }
  }
}

# Base policy for Lambda to execute.
data "aws_iam_policy_document" "base_lambda_policy" {
  statement {
    actions = [
      "logs:*",
      "lambda:InvokeFunction",
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]

    resources = ["*"]
  }
}

# Create Lambda role with AssumeRole policy.
resource "aws_iam_role" "execution_lambda_role" {
  name               = "${var.stage}_${var.name}_lambda"
  assume_role_policy = "${data.aws_iam_policy_document.execution_lambda_policy.json}"
}

# Attach base policy to Lambda role
resource "aws_iam_role_policy" "base_lambda_policy" {
  name   = "${var.stage}_${var.name}_lambda_policy"
  role   = "${aws_iam_role.execution_lambda_role.id}"
  policy = "${data.aws_iam_policy_document.base_lambda_policy.json}"
}

# Lambda
resource "aws_lambda_function" "lambda" {
  function_name    = "${var.stage}_${var.name}"
  filename         = "${var.file}"
  role             = "${aws_iam_role.execution_lambda_role.arn}"
  handler          = "${var.handler}"
  memory_size      = "${var.memory_size}"
  timeout          = "${var.timeout}"
  publish          = "${var.publish}"
  source_code_hash = "${base64sha256(file("${var.file}"))}"
  runtime          = "${var.runtime}"
  description      = "${var.description} (stage: ${var.stage})"

  environment {
    variables = "${var.env_variables}"
  }
}

# Temporary work-around for https://github.com/terraform-providers/terraform-provider-aws/issues/626 -
# aws_lambda_alias uses previous version number.
data "template_file" "function_version" {
  template = "$${function_version}"

  vars {
    function_version = "${aws_lambda_function.lambda.version}"
  }

  depends_on = ["aws_lambda_function.lambda"]
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "${var.stage}"
  function_name    = "${aws_lambda_function.lambda.arn}"
  function_version = "${data.template_file.function_version.rendered}"

  depends_on = ["aws_lambda_function.lambda", "data.template_file.function_version"]
}

# Cloudwatch
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name                = "${var.stage}_${var.name}_lambda_throttles"
  count                     = "${var.enable_monitoring}"                  # Only create on certain stages.
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "2"
  metric_name               = "Throttles"
  namespace                 = "AWS/Lambda"
  period                    = "300"
  statistic                 = "Sum"
  threshold                 = "1"
  alarm_description         = "${var.stage} ${var.name} Lambda Throttles"
  insufficient_data_actions = []

  dimensions {
    FunctionName = "${var.stage}_${var.name}"
    Resource     = "${var.stage}_${var.name}:${var.stage}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

# This is needed for creating the invocation ARN
data "aws_region" "current" {
  current = true
}

output "api_invocation_arn" {
  value = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_alias.lambda_alias.arn}/invocations"
}
