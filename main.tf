terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "jackson-terraform-ca-central1"
    key            = "jenkins/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

provider "github" {
  token = var.github_token
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "cicd" {
  name        = "cicd"
  description = "Allow Jenkins, SSH, and HTTP access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "terraform" {
  ami             = "ami-048d2b60a58148709" # Ubuntu 22.04 LTS (example, confirm region)
  instance_type   = "t2.medium"
  security_groups = [aws_security_group.cicd.name]
  key_name        = "cicd"

  user_data = <<-EOF
  #!/bin/bash
  set -e

  # Update system
  sudo apt update -y
  sudo apt upgrade -y

  # Install Java (required for Jenkins)
  sudo apt install -y fontconfig openjdk-17-jdk

  # Add Jenkins repo and key
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
    /usr/share/keyrings/jenkins-keyring.asc > /dev/null

  echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
    https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
    /etc/apt/sources.list.d/jenkins.list > /dev/null

  # Install Jenkins
  sudo apt update -y
  sudo apt install -y jenkins

  # Start and enable Jenkins
  sudo systemctl daemon-reexec
  sudo systemctl enable jenkins
  sudo systemctl start jenkins

  # Install Docker
  sudo apt install -y docker.io
  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker ubuntu
  sudo usermod -aG docker jenkins

  # Install Go
  sudo apt install -y golang-go

  # Allow Jenkins to access Docker socket
  sudo chmod 666 /var/run/docker.sock

  # Final restart to ensure permissions apply
  sudo systemctl restart jenkins
EOF

  tags = {
    Name = "Jenkins-Server"
  }
}
resource "null_resource" "wait_for_jenkins" {
  depends_on = [aws_instance.terraform]

  provisioner "local-exec" {
    command = <<EOT
      until curl -s --connect-timeout 5 http://${aws_instance.terraform.public_ip}:8080; do
        echo "Waiting for Jenkins to start..."
        sleep 10
      done
    EOT
  }
}

resource "null_resource" "get_jenkins_password" {
  depends_on = [null_resource.wait_for_jenkins]

  provisioner "local-exec" {
    command = <<EOT
      ssh -o StrictHostKeyChecking=no -i ~/.ssh/cicd.pem ec2-user@${aws_instance.terraform.public_ip} \
      "sudo cat /var/lib/jenkins/secrets/initialAdminPassword" > jenkins_initial_password.txt
    EOT
  }
}

data "local_file" "jenkins_password" {
  depends_on = [null_resource.get_jenkins_password]
  filename   = "${path.module}/jenkins_initial_password.txt"
}

resource "null_resource" "create_jenkins_pipeline" {
  depends_on = [data.local_file.jenkins_password, aws_instance.terraform]

  provisioner "local-exec" {
    command = <<EOT
      curl -X POST "http://${aws_instance.terraform.public_ip}:8080/createItem?name=golang-app-pipeline" \
        --user admin:${trimspace(data.local_file.jenkins_password.content)} \
        -H "Content-Type: application/xml" \
        --data-binary "@${path.module}/jenkins.xml"
    EOT
  }
}

resource "null_resource" "trigger_jenkins_pipeline" {
  depends_on = [null_resource.create_jenkins_pipeline]

  provisioner "local-exec" {
    command = <<EOT
      sleep 10
      curl -X POST "http://${aws_instance.terraform.public_ip}:8080/job/golang-app-pipeline/build" \
        --user admin:${trimspace(data.local_file.jenkins_password.content)}
    EOT
  }
}


output "jenkins_public_ip" {
  description = "Public IP of the Jenkins server"
  value       = aws_instance.terraform.public_ip
}
