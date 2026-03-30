output "api_url" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

output "web_bucket" {
  value = aws_s3_bucket.web.bucket
}

output "qr_bucket" {
  value = aws_s3_bucket.qr.bucket
}
