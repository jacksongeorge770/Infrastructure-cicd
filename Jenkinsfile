pipeline {
    agent any
    environment {
        DOCKERHUB_CREDENTIALS = credentials('docker-cred')
        GIT_CREDENTIALS = credentials('git-cred')
        IMAGE_NAME = "jackson216/my-app" // Your Docker Hub repo
        IMAGE_TAG = "${env.BUILD_NUMBER}"
    }
    stages {
        stage('Clone Source Code Repository') {
            steps {
                git branch: 'main', 
                    credentialsId: 'github-credentials', 
                    url: 'https://github.com/jacksongeorge770/cicd-pipeline.git' // Source code repo
            }
        }
        stage('Login to Docker Hub') {
            steps {
                sh 'echo $DOCKERHUB_CREDENTIALS_PSW | docker login -u $DOCKERHUB_CREDENTIALS_USR --password-stdin'
            }
        }
        stage('Build Docker Image') {
            steps {
                sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .'
            }
        }
        stage('Push to Docker Hub') {
            steps {
                sh 'docker push ${IMAGE_NAME}:${IMAGE_TAG}'
            }
        }
    }
    post {
        always {
            emailext (
                subject: "Jenkins Build ${env.BUILD_NUMBER} - ${currentBuild.currentResult}",
                body: """Build ${env.BUILD_NUMBER} finished with status: ${currentBuild.currentResult}.
                         Check console output at ${env.BUILD_URL}""",
                to: 'jacksongeorge770@gmail.com',
                attachLog: true
            )
        }
    }
}