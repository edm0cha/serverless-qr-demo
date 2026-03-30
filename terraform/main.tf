resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "qr" {
  bucket        = "${var.project}-qr-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket" "web" {
  bucket        = "${var.project}-web-${random_id.suffix.hex}"
  website {
    index_document = "index.html"
  }
  force_destroy = true
}

resource "aws_dynamodb_table" "urls" {
  name         = "${var.project}-urls"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "shortCode"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "shortCode"
    type = "S"
  }
}

resource "aws_cognito_user_pool" "this" {
  name = "${var.project}-users"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.project}-client"
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project}-lambda-role-${random_id.suffix.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" },
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["logs:*"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = ["dynamodb:*"],
        Resource = aws_dynamodb_table.urls.arn
      },
      {
        Effect = "Allow",
        Action = ["s3:*"],
        Resource = [
          aws_s3_bucket.qr.arn,
          "${aws_s3_bucket.qr.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project}-api"
  role          = aws_iam_role.lambda_exec.arn
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler       = "app.handler"
  runtime       = "python3.12"
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.urls.name
      QR_BUCKET  = aws_s3_bucket.qr.bucket
    }
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_urls" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /urls"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}
