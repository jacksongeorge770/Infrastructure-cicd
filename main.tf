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
    cidr_blocks = ["0.0.0.0/0"] # allow all outbound
  }
}

resource "aws_instance" "jenkins" {
  ami               = var.ami_id
  instance_type     = "t2.medium"
  security_groups   = [aws_security_group.jenkins_sg.name]
  key_name          = "cicd"
user_data = <<-EOF
  #!/bin/bash

  JENKINS_CLI="/usr/lib/jenkins/jenkins-cli.jar"
  JENKINS_URL="http://localhost:8080"
  ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

  # Wait for Jenkins to be ready
  while ! curl -s $JENKINS_URL/login > /dev/null; do
    echo "Waiting for Jenkins to be ready..."
    sleep 10
  done

  wget $JENKINS_URL/jnlpJars/jenkins-cli.jar -P /tmp

  PLUGINS="configuration-as-code git workflow-aggregator credentials docker-plugin blueocean pipeline-github-lib"

  for plugin in $PLUGINS; do
    java -jar /tmp/jenkins-cli.jar -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD install-plugin $plugin
  done

  java -jar /tmp/jenkins-cli.jar -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD safe-restart

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

output "jenkins_initial_admin_password" {
  value     = file("jenkins_initial_password.txt")
  sensitive = true
}

provider "jenkins" {
  
  server_url = "http://${aws_instance.jenkins.public_ip}:8080"
  username   = "admin"
  password   = trimspace(file("jenkins_initial_password.txt"))
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
  username    = var.dockerhub_username
  password    = var.dockerhub_password
  description = "Docker Hub credentials"
  scope       = "GLOBAL"
}

resource "jenkins_user" "admin" {
  depends_on = [null_resource.get_jenkins_password]
  name       = "admin"
  password   = var.jenkins_admin_password
  email      = "admin@example.com"
  full_name  = "jackson george"
}

resource "jenkins_job" "golang_cicd" {
  name       = "golang-docker-build"
  config_xml = file("${path.module}/jenkins-job.xml")

  depends_on = [
    jenkins_credential.github,
    jenkins_credential.dockerhub
  ]
}
