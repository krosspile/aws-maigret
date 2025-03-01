resource "aws_dynamodb_table" "jobs" {
  name         = "Jobs"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }
}