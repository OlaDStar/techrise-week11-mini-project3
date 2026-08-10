provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "payments" {
  bucket = "quickpayng-payment-data-demo"

  tags = {
    Name = "Payment Data"
  }
}

resource "aws_s3_bucket_public_access_block" "payments" {
  bucket = aws_s3_bucket.payments.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}
