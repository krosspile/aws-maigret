resource "aws_dynamodb_table" "jobs" {
  name         = "Jobs"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }
}

resource "aws_iam_policy" "dynamodb_access" {
  name        = "DynamoDBAccessForEKS"
  description = "Allows EKS managed node groups to access DynamoDB Jobs table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.jobs.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.dynamodb_access.arn
}

resource "aws_iam_role_policy_attachment" "eks_dynamodb_policy_attachment" {
  policy_arn = aws_iam_policy.dynamodb_access.arn
  role       = module.eks.eks_managed_node_groups["eks_nodes"].iam_role_name
}