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


  eks_managed_node_groups = {
    eks_nodes = {
      desired_capacity = 2
      max_capacity     = 3
      min_capacity     = 1

      instance_type = "t3.medium"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks_cluster.eks_cluster_id.endpoint
  token                  = module.eks_cluster.eks_cluster_id.token
  cluster_ca_certificate = base64decode(module.eks_cluster.eks_cluster_id.certificate_authority[0].data)
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.eks_cluster_id.endpoint
    token                  = module.eks_cluster.eks_cluster_id.token
    cluster_ca_certificate = base64decode(module.eks_cluster.eks_cluster_id.certificate_authority[0].data)
  }
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
