# --------------------------------------------------------------------------------
# Required Provider Configuration Variables
# --------------------------------------------------------------------------------

variable "project_id" {
  description = "The ID of the GCP project to deploy resources into."
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources (e.g., asia-southeast1 for Singapore)."
  type        = string
  default     = "asia-southeast1"
}

variable "zone" {
  description = "The GCP zone to deploy the VM (e.g., asia-southeast1-a for Singapore)."
  type        = string
  default     = "asia-southeast1-a"
}

# --------------------------------------------------------------------------------
# Network and Security Variables
# --------------------------------------------------------------------------------

variable "ssh_source_ip" {
  description = "Your public IP address in CIDR notation (e.g., '203.0.113.1/32') to allow secure SSH access. Replace this with your actual IP."
  type        = string
  sensitive   = true # Mark as sensitive to prevent showing the IP in logs
}

variable "network_name" {
  description = "Name for the VPC network."
  type        = string
  default     = "llm-vpc-network"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet."
  type        = string
  default     = "10.10.0.0/20"
}
