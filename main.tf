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
    sudo apt update -y
    sudo apt upgrade -y

    # Install Java
    sudo apt install -y openjdk-11-jdk

    # Add Jenkins repository and install Jenkins
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo tee \
      /usr/share/keyrings/jenkins-keyring.asc > /dev/null
    echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
      https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
      /etc/apt/sources.list.d/jenkins.list > /dev/null
    sudo apt update -y
    sudo apt install -y jenkins

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

    # Install Jenkins Plugin Manager
    sudo curl -L https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.13/jenkins-plugin-manager-2.12.13.jar -o /tmp/jenkins-plugin-manager.jar
    sudo java -jar /tmp/jenkins-plugin-manager.jar --war /usr/share/jenkins/jenkins.war --plugin-download-directory /var/lib/jenkins/plugins --plugin-file /dev/stdin <<PLUGINS
    git
    github
    github-branch-source
    docker-workflow
    pipeline-stage-view
    workflow-aggregator
    credentials
    PLUGINS
    sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins

    # Configure Jenkins credentials for Docker Hub
    sudo mkdir -p /var/lib/jenkins/credentials
    cat <<CRED | sudo tee /var/lib/jenkins/credentials/docker-hub-credentials.xml > /dev/null
    <com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
      <id>docker-hub-credentials</id>
      <description>Docker Hub Credentials</description>
      <username>${var.dockerhub_username}</username>
      <password>${var.dockerhub_password}</password>
    </com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
    CRED
    sudo chown jenkins:jenkins /var/lib/jenkins/credentials/docker-hub-credentials.xml

    # Configure GitHub token for webhook
    sudo mkdir -p /var/lib/jenkins
    cat <<CONFIG | sudo tee /var/lib/jenkins/config.xml > /dev/null
    <?xml version='1.1' encoding='UTF-8'?>
    <hudson>
      <version>2.426.1</version>
      <numExecutors>2</numExecutors>
      <mode>NORMAL</mode>
      <useSecurity>true</useSecurity>
      <authorizationStrategy class="hudson.security.FullControlOnceLoggedInAuthorizationStrategy"/>
      <securityRealm class="hudson.security.HudsonPrivateSecurityRealm"/>
      <disableSignup>true</disableSignup>
      <githubWebHookTokens>
        <com.cloudbees.jenkins.plugins.github.webhook.WebHookToken>
          <name>github-token</name>
          <token>${var.github_token}</token>
        </com.cloudbees.jenkins.plugins.github.webhook.WebHookToken>
      </githubWebHookTokens>
    </hudson>
    CONFIG
    sudo chown jenkins:jenkins /var/lib/jenkins/config.xml

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

resource "github_repository_webhook" "jenkins_webhook" {
  repository = var.github_repository
  configuration {
    url          = "http://${aws_instance.terraform.public_ip}:8080/github-webhook/"
    content_type = "json"
    insecure_ssl = false
  }
  events = ["push"]
}

output "jenkins_public_ip" {
  description = "Public IP of the Jenkins server"
  value       = aws_instance.terraform.public_ip
}
