provider "aws" {
  region = "ca-central-1"
}


provider "jenkins" {
  server_url = "http://${aws_instance.jenkins.public_ip}:8080"
  username   = "admin"
  password   = var.jenkins_admin_password
}

resource "aws_instance" "jenkins" {
  ami           = var.ami_id // From Packer
  instance_type = "t2.medium"
  security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name      = "cicd"
  tags = {
    Name = "Jenkins-Server"
  }
}

resource "aws_security_group" "jenkins_sg" {
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 465
    to_port     = 465
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



resource "jenkins_credential" "github" {
  id          = "github-credentials"
  name        = "github-credentials"
  username    = var.github_username
  password    = var.github_token
  description = "GitHub access token"
  scope       = "GLOBAL"
}

resource "jenkins_credential" "dockerhub" {
  id          = "dockerhub-credentials"
  name        = "dockerhub-credentials"
  username    = var.dockerhub_username
  password    = var.dockerhub_password
  description = "Docker Hub credentials"
  scope       = "GLOBAL"
}









//////////////


provider "aws" {
  region = var.region
}

resource "aws_security_group" "jenkins_sg" {
  name_prefix = "jenkins-"

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
  ami                    = var.ami_id   # <-- Your custom Packer-built AMI
  instance_type          = "t2.medium"
  key_name               = var.key_name
  security_group_ids     = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = true

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

provider "jenkins" {
  depends_on = [null_resource.wait_for_jenkins]
  server_url = "http://${aws_instance.jenkins.public_ip}:8080"
  username   = "admin"
  password   = var.jenkins_admin_password
}

resource "jenkins_credential" "github" {
  id          = "github-credentials"
  name        = "github-credentials"
  username    = var.github_username
  password    = var.github_token
  description = "GitHub access token"
  scope       = "GLOBAL"
}

resource "jenkins_credential" "dockerhub" {
  id          = "dockerhub-credentials"
  name        = "dockerhub-credentials"
  username    = var.dockerhub_username
  password    = var.dockerhub_password
  description = "Docker Hub credentials"
  scope       = "GLOBAL"
}

resource "jenkins_pipeline" "cicd" {
  name   = "my-cicd-pipeline"
  config = file("${path.module}/pipeline.xml")
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}
