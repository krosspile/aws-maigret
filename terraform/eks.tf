module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19.0"
  name    = "vpc-sistemi-cloud"
  cidr    = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

}


module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.33.1"
  cluster_name    = "cluster-sistemi-cloud"
  cluster_version = "1.32"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true



  node_security_group_additional_rules = {
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }


  eks_managed_node_groups = {
    eks_nodes = {
      desired_capacity = 1
      max_capacity     = 1
      min_capacity     = 1

      instance_type = ["t3.medium"]
    }
  }
}

data "aws_eks_cluster" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks.cluster_name]
}

data "aws_eks_cluster_auth" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks.cluster_name]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  token                  = data.aws_eks_cluster_auth.cluster.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
}


provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    token                  = data.aws_eks_cluster_auth.cluster.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  }

}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}


resource "helm_release" "keda" {
  name = "keda"

  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  version          = "2.16.1"
  create_namespace = true
}

data "aws_ecr_repository" "service" {
  name = "app"
}

variable "deploy_k8s" {
  description = "Set to true to deploy Kubernetes resources after EKS creation"
  type        = bool
  default     = false
}



### Kubernetes Namespace
resource "kubernetes_namespace" "app_ns" {
  count = var.deploy_k8s ? 1 : 0
  metadata {
    name = "app"
  }
}

### Kubernetes Deployment
resource "kubernetes_manifest" "app_deployment" {
  count = var.deploy_k8s ? 1 : 0
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "app"
      namespace = "app"
      labels = {
        app = "app"
      }
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "app"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "app"
          }
        }
        spec = {
          containers = [{
            name  = "app"
            image = "${data.service.repository_url}:latest"

            imagePullPolicy = "Always"

            env = [
              { name = "AWS_REGION", value = "us-east-1" },
              { name = "SQS_QUEUE_URL", value = aws_sqs_queue.jobs_queue.id }
            ]
          }]

        }
      }
    }
  }
  depends_on = [kubernetes_namespace.app_ns]
}

### KEDA Scaler per SQS
resource "kubernetes_manifest" "keda_scaled_object" {
  count = var.deploy_k8s ? 1 : 0
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "app-scaler"
      namespace = "app"
    }
    spec = {
      scaleTargetRef = {
        name = "app"
      }
      minReplicaCount = 1
      maxReplicaCount = 5
      pollingInterval = 15
      triggers = [{
        type = "aws-sqs-queue"
        metadata = {
          queueURL      = aws_sqs_queue.jobs_queue.id
          queueLength   = "5"
          awsRegion     = "us-east-1"
          identityOwner = "operator"
        }
      }]
    }
  }
  depends_on = [helm_release.keda, kubernetes_manifest.app_deployment]
}


output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "subnets" {
  description = "List of subnets"
  value       = module.vpc.private_subnets
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

