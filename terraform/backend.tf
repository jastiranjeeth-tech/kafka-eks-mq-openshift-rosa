terraform {
  backend "s3" {
    bucket         = "kafka-terraform-state-831488932214"
    key            = "kafka-eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
