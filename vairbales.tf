variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "aws_access_key" {
  type      = string
  sensitive = true
}
variable "aws_secret_key" {
  type      = string
  sensitive = true
}

variable "public_key_path" {
  type        = string
  description = "Path to the public SSH key used for EC2 and passed into OpenShift"
}

variable "base_domain" {
  type        = string
  description = "e.g. softekh.com"
}
variable "cluster_name" {
  type        = string
  description = "e.g. sample-name"
}
# variables.tf
variable "root_volume_size" {
  description = "Root disk size (GiB) for the installer EC2 host"
  type        = number
  default     = 40     # safe head-room; change in tfvars or CLI if needed
}
