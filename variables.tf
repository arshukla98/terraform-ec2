variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for EC2 instances"
}

variable "instance_count" {
  type        = number
  default     = 2
  description = "Number of EC2 instances to create"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 in us-east-1
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment name"
}

variable "instance_name" {
  type        = string
  default     = "web-server"
  description = "Name tag for EC2 instances"
}
