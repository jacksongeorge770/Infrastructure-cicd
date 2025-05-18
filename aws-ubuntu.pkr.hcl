packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "ca-central-1"
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "latest-jenkin-packer"
  instance_type = "t2.medium"
  region        = var.region
  source_ami    = "ami-08355844f8bc94f55"
  ssh_username  = "ubuntu"
}

build {
  name    = "jenkins-docker-build"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = <<-EOT
      #!/bin/bash

      sudo apt-get update -y
      sudo apt-get install -y openjdk-17-jdk

      curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
      echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
      sudo apt-get update -y
      sudo apt-get install -y jenkins
      sudo systemctl enable jenkins
      sudo systemctl start jenkins

      sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      sudo apt-get update -y
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io
      sudo usermod -aG docker ubuntu

      echo 'Waiting for Jenkins to fully start...'
      until curl -s http://localhost:8080/login > /dev/null; do
        sleep 10
      done

      wget http://localhost:8080/jnlpJars/jenkins-cli.jar -P /tmp

      ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

      PLUGINS=(
        configuration-as-code
        git
        workflow-aggregator
        credentials
        docker-plugin
        blueocean
        pipeline-github-lib
      )

      for plugin in "${PLUGINS[@]}"; do
        echo "Installing plugin: $plugin"
        java -jar /tmp/jenkins-cli.jar -s http://localhost:8080 -auth admin:$ADMIN_PASSWORD install-plugin $plugin
      done

      java -jar /tmp/jenkins-cli.jar -s http://localhost:8080 -auth admin:$ADMIN_PASSWORD safe-restart

      # Wait a bit for Jenkins to restart
      sleep 30
    EOT
  }
}
