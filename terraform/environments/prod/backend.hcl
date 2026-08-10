bucket         = "k8s-multi-master-terraform-state-<YOUR_ACCOUNT_ID>"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "k8s-multi-master-terraform-locks"
encrypt        = true
