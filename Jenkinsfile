pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'jackson216/jenkin' // Your Docker Hub repository
    }

    stages {
        stage('Clone Repository') {
            steps {
                git credentialsId: 'git-cred', url: 'https://github.com/jacksongeorge770/cicd-pipeline.git'
        }

        stage('Build Docker Image') {
            steps {
                script {
                    sh 'docker build -t $DOCKER_IMAGE:latest .'
                }
            }
        }

        stage('Login to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'docker-cred',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    sh 'docker push $DOCKER_IMAGE:latest'
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                script {
                    sh '''
                        docker rm -f myapp-container || true
                        docker run -d --name myapp-container -p 8081:8080 $DOCKER_IMAGE:latest
                    '''
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline finished: ${currentBuild.currentResult}"
        }

        success {
            emailext(
                subject: "✅ Jenkins Build Success: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "The build completed successfully.\nCheck the job: ${env.BUILD_URL}",
                to: "jacksongeorgeg87@gmail.com"
            )
        }

        failure {
            emailext(
                subject: "❌ Jenkins Build FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "The build failed. Please review logs: ${env.BUILD_URL}",
                to: "jacksongeorgeg87@gmail.com"
            )
        }
    }
}
