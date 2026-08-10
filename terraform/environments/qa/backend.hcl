bucket         = "k8s-multi-master-terraform-state-<YOUR_ACCOUNT_ID>"
key            = "qa/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "k8s-multi-master-terraform-locks"
encrypt        = true
