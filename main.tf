provider "aws" {
  version = "~> 5.0"
  region  = "ca-central-1"
}

provider "aws" {
  region = "ca-central-1"
}


provider "jenkins" {
  server_url = "http://${aws_instance.jenkins.public_ip}:8080"
  username   = "admin"
  password   = var.jenkins_admin_password
}

resource "aws_instance" "jenkins" {
  ami               = "062949cfb8b984e65"
  instance_type     = "t2.medium"
  security_groups = [aws_security_group.jenkins_sg.name] # NOTE: plural and list
  key_name          = "cicd"

  tags = {
    Name = "Jenkins-Server"
  }
}

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Allow Jenkins and SSH access"
  vpc_id      = data.aws_vpc.default.id


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Jenkins UI
  }
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound
  }
}

data "aws_vpc" "default" {
  default = true
}


resource "jenkins_credential" "github" {
  id          = "github-credentials"
  name        = "github-credentials"
  username    = "jacksongeorge770"
  password    = var.github_token
  description = "GitHub access token"
  scope       = "GLOBAL"
}

resource "jenkins_credential" "dockerhub" {
  id          = "dockerhub-credentials"
  name        = "dockerhub-credentials"
  username    = "jackson216"
  password    = var.dockerhub_password
  description = "Docker Hub credentials"
  scope       = "GLOBAL"
}


resource "null_resource" "wait_for_jenkins" {
  depends_on = [aws_instance.jenkins]

  provisioner "local-exec" {
    command = "sleep 90"
  }
}

provider "jenkins" {
  depends_on = [null_resource.wait_for_jenkins]
  server_url = "http://${aws_instance.jenkins.public_ip}:8080"
  username   = "admin"
  password   = var.jenkins_admin_password
}









