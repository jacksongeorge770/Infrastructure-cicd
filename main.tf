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
      source  = "taiidani/jenkins" # Correct provider source
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
  ami               = "062949cfb8b984e65"
  instance_type     = "t2.medium"
  security_groups   = [aws_security_group.jenkins_sg.name]
  key_name          = "cicd"
user_data = <<-EOF
  #!/bin/bash

  JENKINS_URL="http://localhost:8080"
  ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

  # Wait for Jenkins to be ready
  while ! curl -s $JENKINS_URL/login > /dev/null; do
    echo "Waiting for Jenkins to be ready..."
    sleep 10
  done

  # Download Jenkins CLI
  wget $JENKINS_URL/jnlpJars/jenkins-cli.jar -P /tmp
  JENKINS_CLI="/tmp/jenkins-cli.jar"

  # Install plugins
  PLUGINS="configuration-as-code git workflow-aggregator credentials docker-plugin blueocean pipeline-github-lib"
  for plugin in $PLUGINS; do
    java -jar $JENKINS_CLI -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD install-plugin $plugin
  done

  # Create GitHub credentials
  cat <<EOT > /tmp/github-credentials.xml
  <com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
    <scope>GLOBAL</scope>
    <id>github-credentials</id>
    <description>GitHub access token</description>
    <username>jacksongeorge770</username>
    <password>${var.github_token}</password>
  </com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  EOT
  java -jar $JENKINS_CLI -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD create-credentials-by-xml system::system::jenkins _ < /tmp/github-credentials.xml

  # Create DockerHub credentials
  cat <<EOT > /tmp/dockerhub-credentials.xml
  <com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
    <scope>GLOBAL</scope>
    <id>dockerhub-credentials</id>
    <description>Docker Hub credentials</description>
    <username>${var.dockerhub_username}</username>
    <password>${var.dockerhub_password}</password>
  </com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  EOT
  java -jar $JENKINS_CLI -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD create-credentials-by-xml system::system::jenkins _ < /tmp/dockerhub-credentials.xml

  # Configure admin user (using groovy script to update admin account)
  cat <<EOT > /tmp/update-admin.groovy
  import hudson.model.User
  import hudson.security.HudsonPrivateSecurityRealm

  def user = User.get('admin', true)
  user.setFullName('jackson george')
  user.addProperty(new hudson.security.HudsonPrivateSecurityRealm.Details('${var.jenkins_admin_password}', 'admin@example.com'))
  user.save()
  EOT
  java -jar $JENKINS_CLI -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD groovy /tmp/update-admin.groovy

  # Clean up temporary files
  rm -f /tmp/github-credentials.xml /tmp/dockerhub-credentials.xml /tmp/update-admin.groovy

  # Restart Jenkins to apply changes
  java -jar $JENKINS_CLI -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD safe-restart
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
