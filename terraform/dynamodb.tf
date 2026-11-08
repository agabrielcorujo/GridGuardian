resource "aws_dynamodb_table" "reports" {
  name         = "GridGuardian"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "zipcode"
  range_key    = "condition-timestamp"
  attribute {
    name = "condition-timestamp"
    type = "S"
  }
  attribute {
    name = "zipcode"
    type = "S"
  }
}
