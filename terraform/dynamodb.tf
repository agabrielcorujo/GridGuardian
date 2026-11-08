import {
  to = aws_dynamodb_table.reports
  id = var.reports_table_name
}

resource "aws_dynamodb_table" "reports" {
  name         = var.reports_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "zipcode"
  range_key    = "condition-timestamp"

  attribute {
    name = "zipcode"
    type = "S"
  }

  attribute {
    name = "condition-timestamp"
    type = "S"
  }
}
