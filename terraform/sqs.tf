resource "aws_sqs_queue" "jobs_queue" {
  name                      = "jobs"
  delay_seconds             = 0
  receive_wait_time_seconds = 0
  sqs_managed_sse_enabled   = true

}

resource "aws_iam_policy" "lambda_sqs_policy" {
  name        = "lambda_sqs_policy"
  description = "Allows Lambda to send messages to SQS"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.jobs_queue.arn
      }
    ]
  })
}


resource "aws_iam_policy" "eks_sqs_policy" {
  name        = "eks_sqs_policy"
  description = "Allows EKS to send message and receive to SQS"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ListQueues",
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.jobs_queue.arn
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_sqs_attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_sqs_policy.arn
}

resource "aws_iam_role_policy_attachment" "eks_sqs_policy_attachment" {
  policy_arn = aws_iam_policy.eks_sqs_policy.arn
  role       = module.eks.eks_managed_node_groups["eks_nodes"].iam_role_name
}

output "sqs_queue_url" {
  value = aws_sqs_queue.jobs_queue.url
}