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
    jenkins = {
      source  = "taiidani/jenkins"
      version = "~> 0.5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Allow Jenkins and SSH access"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "jenkins" {
  ami               = "ami-062949cfb8b984e65"  
  instance_type     = "t2.medium"
  security_groups   = [aws_security_group.jenkins_sg.name]
  key_name          = "cicd"

  user_data = <<-EOF
    #!/bin/bash
    # Simple user_data: Jenkins installs itself by default in this AMI or install manually if needed
    # You can add plugin installation here if you want to automate that part later.
  EOF

  tags = {
    Name = "Jenkins-Server"
  }
}

resource "null_resource" "wait_for_jenkins" {
  depends_on = [aws_instance.jenkins]

  provisioner "local-exec" {
    command = "sleep 90"
  }
}

resource "null_resource" "get_jenkins_password" {
  depends_on = [null_resource.wait_for_jenkins]

  provisioner "local-exec" {
    command = <<EOT
      ssh -o StrictHostKeyChecking=no -i ~/.ssh/cicd.pem ec2-user@${aws_instance.jenkins.public_ip} \
      "sudo cat /var/lib/jenkins/secrets/initialAdminPassword" > jenkins_initial_password.txt
    EOT
  }
}

data "local_file" "jenkins_password" {
  depends_on = [null_resource.get_jenkins_password]
  filename   = "${path.module}/jenkins_initial_password.txt"
}

provider "jenkins" {
  server_url = "http://${aws_instance.jenkins.public_ip}:8080"
  username   = "admin"
  password   = trimspace(data.local_file.jenkins_password.content)
}

# resource "jenkins_script" "create_golang_job" {
#   script = file("${path.module}/create_golang_job.groovy")
# }
