# VPC Configurations

This folder contains VPC configuration files that can be referenced by cluster configs.

## Creating a New VPC

Use the create-vpc.sh script:

```bash
# Create VPC with 3 AZs (recommended for production)
./scripts/create-vpc.sh <vpc-name> <region> [az-count] [cidr]

# Examples:
./scripts/create-vpc.sh prod-vpc us-east-2 3 10.0.0.0/16
./scripts/create-vpc.sh dev-vpc us-west-2 1 10.1.0.0/16
```

## Using an Existing VPC

1. Get subnet information:
   ```bash
   aws ec2 describe-subnets --region <region> \
     --filters "Name=vpc-id,Values=<vpc-id>" \
     --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' \
     --output table
   ```

2. Create a VPC config file (e.g., `my-vpc.env`):
   ```bash
   VPC_NAME="my-vpc"
   VPC_ID="vpc-xxxxx"
   AWS_REGION="us-east-2"
   VPC_CIDR="10.0.0.0/16"
   
   # List all subnet IDs (public + private for public clusters)
   ALL_SUBNET_IDS="subnet-xxx,subnet-yyy,subnet-zzz"
   ```

3. Reference in cluster config:
   ```bash
   # In configs/my-cluster.env
   SUBNET_IDS="subnet-xxx,subnet-yyy,subnet-zzz"
   MACHINE_CIDR="10.0.0.0/16"
   ```

## VPC Requirements for ROSA HCP

- **Public clusters**: Need both public AND private subnets
- **Private clusters**: Only need private subnets
- **NAT Gateway**: Required for private subnets (created by rosa create network)
- **Internet Gateway**: Required for public subnets
