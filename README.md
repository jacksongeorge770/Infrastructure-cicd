## 🖼️ Overview
📌 Project Overview: Terraform Automation with Jenkins & GitHub Actions
This project automates the end-to-end infrastructure provisioning and deployment pipeline using Terraform, GitHub Actions, and Jenkins on AWS.

## 🖼️ Architecture Diagram

![Architecture](./assets/Terraform-2ndpro.drawio.png)

🎯 Goal
To create a CI/CD workflow that:

Provisions infrastructure using Terraform

Uses a remote backend (S3 + DynamoDB) for secure state management

Triggers a Jenkins job that pulls pipeline logic from a separate repository and handles the deployment

🧱 Infrastructure Provisioning
Provisioned using: Terraform

Resources created:

EC2 instance (to host Jenkins)

S3 bucket (for remote Terraform state)

DynamoDB table (for state locking)

🔁 CI/CD Workflow
CI: GitHub Actions triggers Terraform apply automatically 

CD: GitHub Action then triggers Jenkins (via webhook or token)

Jenkins: Reads a Jenkinsfile in this repo, and:

Clones a separate app repository

Runs build/test/deploy pipeline

🔐 State Management
Backend: S3 bucket with versioning

Locking: DynamoDB table to prevent concurrent runs

🛠️ Technologies Used
Terraform – Infrastructure as Code

GitHub Actions – CI and automation pipeline

AWS – EC2, S3, DynamoDB

Jenkins – CD and deployment automation

✅ Outcome
Fully automated, version-controlled infrastructure and CI/CD pipeline mimicing real-world scenario

Secure remote state backend

Clean separation of responsibilities between provisioning (Terraform) and deployment (Jenkins)













🛠️ Click the Workflow (e.g., "Terraform Manual Trigger")
You'll see it listed in the left panel.

▶️ Click the "Run workflow" button



Checkout your repo code

Setup Terraform

Configure AWS credentials

Run terraform init

Run terraform plan (using the secrets you provide as environment variables)

Run terraform apply -auto-approve (applying the changes automatically)



