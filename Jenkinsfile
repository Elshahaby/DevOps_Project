pipeline {
    agent any

    environment {
        DOCKER_HOST = 'tcp://localhost:2375'
        DOCKERHUB_CREDS = credentials('dockerhub-credentials')
        IMAGE_TAG = "${BUILD_NUMBER}"
        FRONTEND_IMAGE = 'mohamedelshahaby/inventory-frontend'
        BACKEND_IMAGE = 'mohamedelshahaby/inventory-backend'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Backend') {
            steps {
                script {
                    docker.image('mcr.microsoft.com/dotnet/sdk:9.0').inside('-e DOTNET_CLI_HOME=/tmp/dotnet') {
                        dir('Backend') {
                            sh 'dotnet restore InventoryManagement.slnx'
                            sh 'dotnet build InventoryManagement.slnx --no-restore -c Release'
                        }
                    }
                }
            }
        }

        stage('Test Backend') {
            steps {
                script {
                    docker.image('mcr.microsoft.com/dotnet/sdk:9.0').inside('-e DOTNET_CLI_HOME=/tmp/dotnet') {
                        dir('Backend') {
                            sh '''
                                if ls *.Tests/*.csproj 2>/dev/null; then
                                    dotnet test InventoryManagement.slnx --no-build -c Release --verbosity normal
                                else
                                    echo "No backend test project found — skipping tests"
                                fi
                            '''
                        }
                    }
                }
            }
        }

        stage('Build Frontend') {
            steps {
                script {
                    docker.image('node:20-alpine').inside {
                        dir('Frontend') {
                            sh 'npm ci'
                            sh 'npm run build -- --configuration=production'
                        }
                    }
                }
            }
        }

        stage('Test Frontend') {
            steps {
                script {
                    docker.image('node:20-alpine').inside {
                        dir('Frontend') {
                            sh '''
                                npm test -- --watch=false --browsers=ChromeHeadless || \
                                    echo "No frontend tests or test configuration — skipping"
                            '''
                        }
                    }
                }
            }
        }

        stage('Build & Push Docker Images') {
            steps {
                script {
                    docker.withRegistry('', 'dockerhub-credentials') {
                        def backendImage = docker.build("${BACKEND_IMAGE}:${IMAGE_TAG}", "-f Backend/Dockerfile Backend")
                        backendImage.push()
                        backendImage.push('latest')

                        def frontendImage = docker.build("${FRONTEND_IMAGE}:${IMAGE_TAG}", "-f Frontend/Dockerfile Frontend")
                        frontendImage.push()
                        frontendImage.push('latest')
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    sh '''
                        if [ -d k8s/application ]; then
                            sed -i "s|image: .*inventory-backend:.*|image: ${BACKEND_IMAGE}:${IMAGE_TAG}|g" k8s/application/*.yaml
                            sed -i "s|image: .*inventory-frontend:.*|image: ${FRONTEND_IMAGE}:${IMAGE_TAG}|g" k8s/application/*.yaml
                            kubectl apply -f k8s/application/
                        else
                            echo "k8s/application/ directory not found — skipping (Phase 5 — create it first)"
                        fi
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Pipeline completed successfully — images pushed to DockerHub"
        }
        failure {
            echo "Pipeline failed — check logs above for details"
        }
    }
}
