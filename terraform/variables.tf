variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "deploy_k8s" {
  description = "Set to true to deploy Kubernetes resources after EKS creation"
  type        = bool
  default     = false
}
