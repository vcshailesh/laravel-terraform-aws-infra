terraform {
  backend "s3" {
    bucket         = "laravel-tfstate-157788111029"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
    profile        = "shailesh-aws"
  }
}