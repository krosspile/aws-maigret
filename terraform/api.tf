data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "lambda_logging_policy" {
  name        = "lambda_logging_policy"
  description = "Allows Lambda to write logs to CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging_attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_logging_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/api_lambda"
  retention_in_days = 7
}

data "archive_file" "lambda_src" {
  type        = "zip"
  source_dir  = "../src/api"
  output_path = "lambda.zip"
}

resource "aws_lambda_function" "api_lambda" {
  filename      = data.archive_file.lambda_src.output_path
  function_name = "api_lambda"
  handler       = "main.handle"
  role          = aws_iam_role.iam_for_lambda.arn
  runtime       = "python3.10"

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.jobs_queue.id
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_log_group]
}

resource "aws_apigatewayv2_api" "sistemi-cloud-api" {
  name          = "api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.sistemi-cloud-api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_route" {
  api_id    = aws_apigatewayv2_api.sistemi-cloud-api.id
  route_key = "GET /jobs"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.sistemi-cloud-api.id
  route_key = "POST /jobs"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.sistemi-cloud-api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_lambda" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.sistemi-cloud-api.execution_arn}/*/*"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.sistemi-cloud-api.api_endpoint
}
