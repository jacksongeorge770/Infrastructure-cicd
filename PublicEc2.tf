
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "main-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "main-igw"
  }
}

# Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ca-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

# Route Table and Association
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "public_rt_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group
resource "aws_security_group" "allow_ssh_http_https" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

  tags = {
    Name = "allow-ssh-http-https-8080"
  }
}

# EC2 Instance
resource "aws_instance" "jenkin_instance" {
  ami                         = "ami-08355844f8bc94f55" # Ubuntu 22.04 in ca-central-1
  instance_type               = "t2.medium"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh_http_https.id]
  key_name                    = "cicd" # Use your existing AWS key pair
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y fontconfig openjdk-17-jre -y

              # Add Jenkins key and repo
              curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee \
              /usr/share/keyrings/jenkins-keyring.asc > /dev/null

              echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
              https://pkg.jenkins.io/debian binary/ | sudo tee \
              /etc/apt/sources.list.d/jenkins.list > /dev/null

              # Install Jenkins
              sudo apt update -y
              sudo apt install jenkins -y

              # Start Jenkins
              sudo systemctl enable jenkins
              sudo systemctl start jenkins
              EOF

  tags = {
    Name = "jenkins-ubuntu-instance"
  }
}


resource "null_resource" "post_jenkins_setup" {
  depends_on = [aws_instance.jenkin_instance]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/Downloads/cicd.pem")
      host        = aws_instance.jenkin_instance.public_ip
    }

    inline = [
      "echo Hello from Jenkins EC2",
      "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
    ]
  }
}