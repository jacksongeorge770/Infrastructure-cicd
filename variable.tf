variable "region" {
  type    = string
  default = "ca-central-1"
}

variable "ami_id" {
  description = "Packer-built AMI ID"
  type        = string
}

variable "jenkins_admin_password" {
  description = "Jenkins admin password"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

variable "dockerhub_username" {
  description = "Docker Hub username"
  type        = string
}

variable "dockerhub_password" {
  description = "Docker Hub password"
  type        = string
  sensitive   = true
}

variable "github_repository" {
  description = "GitHub repository name for Repo A (e.g., jacksongeorge770/Infrastructure-cicd)"
}
