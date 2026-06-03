pipeline {
    agent any

    parameters {
        string(
            name: 'GIT_BRANCH',
            description: 'Git Branch name'
        )
        choice(
            name: 'TERRAFORM_ACTION',
            choices: ['apply', 'destroy'],
            description: 'Choose Terraform action to execute'
        )
        string(
            name: 'AWS_REGION',
            defaultValue: 'us-east-1',
            description: 'AWS region for EC2 instances'
        )
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
    }

    environment {
        AWS_REGION = "${params.AWS_REGION}"
        ALERT_ENDPOINT = "http://172.30.46.174:30080/alerts"
        // ALERT_ENDPOINT = "https://stg01.aziro.com/api/v1/webhooks/387a6270-8e3c-42e7-8f53-8b98a5175356"
        TERRAFORM_VERSION = "1.14.3"
        GIT_REPO = "https://github.com/arshukla98/terraform-ec2.git"
        GIT_BRANCH = "${params.GIT_BRANCH}"
        GIT_CREDENTIALS = "github-user_token2"
        AWS_ACCESS_KEY_CREDENTIAL = "aws-access-key-id"
        AWS_SECRET_KEY_CREDENTIAL = "aws-secret-access-key"
    }

    stages {
        stage('Validate Parameters') {
            steps {
                script {
                    echo "Validating required parameters..."
                    
                    if (!params.GIT_BRANCH || params.GIT_BRANCH.trim() == '') {
                        echo "✗ ERROR: GIT_BRANCH parameter is required but not specified"
                        currentBuild.result = 'NOT_BUILT'
                        return
                    }
                    
                    echo "✓ GIT_BRANCH: ${params.GIT_BRANCH}"
                }
            }
        }

        stage('Checkout') {
            steps {
                script {
                    echo "Cloning Terraform EC2 repository..."

                    def ts = sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim()
                    env.START_TIME = ts
                    
                    echo "Start time: ${env.START_TIME}"
                    
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: "*/${GIT_BRANCH}"]],
                        userRemoteConfigs: [[
                            url: GIT_REPO,
                            credentialsId: GIT_CREDENTIALS
                        ]]
                    ])
                }
            }
        }

        stage('Restore Terraform State') {
            steps {
                script {
                    echo "Attempting to restore Terraform state from persistent location..."
                    def stateDir = "/tmp/jenkins-terraform-states/${env.JOB_NAME}"
                    
                    sh """
                        mkdir -p ${stateDir}
                        
                        if [ -f ${stateDir}/terraform.tfstate ]; then
                            echo "✓ Restoring state from ${stateDir}"
                            cp -v ${stateDir}/terraform.tfstate* . 2>/dev/null || true
                            cp -v ${stateDir}/.terraform.lock.hcl . 2>/dev/null || true
                            export STATE_EXISTS="true"
                        else
                            echo "⚠ No previous state found - fresh deployment"
                            export STATE_EXISTS="false"
                        fi
                    """
                    
                    // Check if state file exists locally after restore
                    if (fileExists('terraform.tfstate')) {
                        env.STATE_EXISTS = "true"
                    } else {
                        env.STATE_EXISTS = "false"
                    }
                    
                    echo "DEBUG: STATE_EXISTS = ${env.STATE_EXISTS}"
                }
            }
        }

        stage('Verify Prerequisites') {
            steps {
                script {
                    echo "Verifying Terraform and AWS CLI..."
                    withCredentials([
                        string(credentialsId: "${AWS_ACCESS_KEY_CREDENTIAL}", variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: "${AWS_SECRET_KEY_CREDENTIAL}", variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set +x
                            terraform version
                            aws --version
                            aws sts get-caller-identity
                        '''
                    }
                }
            }
        }

        stage('Terraform Init') {
            steps {
                script {
                    echo "Initializing Terraform..."
                    withCredentials([
                        string(credentialsId: "${AWS_ACCESS_KEY_CREDENTIAL}", variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: "${AWS_SECRET_KEY_CREDENTIAL}", variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set +x
                            terraform init \
                                -upgrade \
                                -lock=true
                        '''
                    }
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                script {
                    echo "Validating Terraform configuration..."
                    
                    sh '''
                        export TF_LOG=DEBUG
                        terraform validate
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                script {
                    echo "Creating Terraform plan..."
                    withCredentials([
                        string(credentialsId: "${AWS_ACCESS_KEY_CREDENTIAL}", variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: "${AWS_SECRET_KEY_CREDENTIAL}", variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            terraform plan \
                                -out=tfplan \
                                -lock=true \
                                -input=false
                        '''
                    }
                }
            }
        }

        stage('Terraform Apply') {
            when {
                expression { params.TERRAFORM_ACTION == 'apply' }
            }
            steps {
                script {
                    echo "Checking for changes in Terraform plan..."
                    
                    // Debug: Display full plan JSON (avoid broken pipe)
                    echo "DEBUG: Full plan JSON:"
                    sh '''
                        terraform show -json tfplan | jq . > /tmp/tfplan_debug.json 2>&1
                        head -50 /tmp/tfplan_debug.json
                    '''
                    
                    // Check if there are any changes (resources OR outputs)
                    echo "DEBUG: Checking for resource and output changes..."
                    def hasResourceChanges = sh(script: 'terraform show -json tfplan | jq \'.resource_changes | map(select(.change.actions | any(. == "create" or . == "update" or . == "delete"))) | length\'', returnStdout: true).trim()
                    def resourceChangeCount = hasResourceChanges.toInteger()
                    
                    // Check for output changes by examining planned_values.outputs
                    def hasOutputChanges = sh(script: 'terraform show -json tfplan | jq \'.planned_values.outputs // {} | length\'', returnStdout: true).trim()
                    def outputChangeCount = hasOutputChanges.toInteger()
                    
                    echo "DEBUG: Resource changes count: ${resourceChangeCount}"
                    echo "DEBUG: Planned outputs count: ${outputChangeCount}"
                    
                    // Debug: Show all resource changes
                    echo "DEBUG: All resource changes:"
                    sh '''
                        terraform show -json tfplan | jq '.resource_changes | map({address, actions: .change.actions})'
                    '''
                    
                    def totalChanges = resourceChangeCount + outputChangeCount
                    if (totalChanges == 0) {
                        echo "⚠ No changes detected in configuration - skipping apply and state update"
                        echo "DEBUG: Setting HAS_CHANGES to 'false'"
                        env.HAS_CHANGES = "false"
                        env.FRESH_DEPLOYMENT = "false"
                    } else {
                        // Determine if this is a fresh deployment (creating resources for first time)
                        if (env.STATE_EXISTS == "false" && resourceChangeCount > 0) {
                            env.FRESH_DEPLOYMENT = "true"
                            echo "DEBUG: Fresh deployment detected (first resource creation)"
                            env.HAS_CHANGES = "true"
                        } else {
                            env.FRESH_DEPLOYMENT = "false"
                            echo "DEBUG: Not a fresh deployment"
                            // For output-only changes or updates, keep HAS_CHANGES as false
                            if (resourceChangeCount > 0) {
                                env.HAS_CHANGES = "true"
                            } else {
                                env.HAS_CHANGES = "false"
                            }
                        }
                        echo "Applying Terraform plan..."
                        withCredentials([
                            string(credentialsId: "${AWS_ACCESS_KEY_CREDENTIAL}", variable: 'AWS_ACCESS_KEY_ID'),
                            string(credentialsId: "${AWS_SECRET_KEY_CREDENTIAL}", variable: 'AWS_SECRET_ACCESS_KEY')
                        ]) {
                            sh '''
                                terraform apply \
                                    -lock=true \
                                    -input=false \
                                    tfplan
                            '''
                        }
                        
                        // After successful apply, mark state as existing
                        env.STATE_EXISTS = "true"
                        
                        echo "✓ Terraform apply successful - archiving state..."
                        def stateDir = "/tmp/jenkins-terraform-states/${env.JOB_NAME}"
                        
                        sh """
                            mkdir -p ${stateDir}
                            cp -v terraform.tfstate* ${stateDir}/ 2>/dev/null || true
                            cp -v .terraform.lock.hcl ${stateDir}/ 2>/dev/null || true
                            echo "✓ State saved to ${stateDir}"
                        """
                        
                        archiveArtifacts artifacts: 'terraform.tfstate*,.terraform.lock.hcl', allowEmptyArchive: true
                    }
                }
            }
        }

        stage('Retrieve Instance Information') {
            when {
                expression { params.TERRAFORM_ACTION == 'apply' && env.STATE_EXISTS == 'true' && env.FRESH_DEPLOYMENT == 'false' }
            }
            steps {
                script {
                    echo "DEBUG: Entering Retrieve Instance Information stage"
                    echo "DEBUG: STATE_EXISTS = ${env.STATE_EXISTS}"
                    echo "DEBUG: FRESH_DEPLOYMENT = ${env.FRESH_DEPLOYMENT}"
                    echo "Retrieving EC2 instance information..."
                    withCredentials([
                        string(credentialsId: "${AWS_ACCESS_KEY_CREDENTIAL}", variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: "${AWS_SECRET_KEY_CREDENTIAL}", variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            echo "=== Instance Information ==="
                            terraform output
                            
                            echo ""
                            echo "=== Retrieving Instance Names ==="
                            INSTANCE_NAMES=$(terraform output -raw instance_names)
                            echo "Instance Names: ${INSTANCE_NAMES}"
                        '''
                    }
                }
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.TERRAFORM_ACTION == 'destroy' }
            }
            steps {
                script {
                    echo "WARNING: Destroying EC2 instances..."
                    timeout(time: 10, unit: 'MINUTES') {
                        input message: 'Confirm EC2 instance destruction?', ok: 'Destroy'
                    }
                    withCredentials([
                        string(credentialsId: "${AWS_ACCESS_KEY_CREDENTIAL}", variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: "${AWS_SECRET_KEY_CREDENTIAL}", variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            terraform destroy \
                                -lock=true \
                                -auto-approve \
                                -input=false
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                cleanWs()
            }
        }
        success {
            echo "✓ Pipeline executed successfully!"
        }
        failure {
            script {
                echo '✗ Pipeline failed!'
                
                // Only send alert if on main branch
                if (params.GIT_BRANCH == 'main') {
                    def ts = sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim()
                    env.END_TIME = ts
                    
                    echo "Failure time: ${env.END_TIME}"

                    def payload = """
                    {
                        "receiver": "jenkins-alerts",
                        "status": "firing",
                        "alerts": [
                            {
                                "status": "firing",
                                "labels": {
                                    "alertname": "JenkinsPipelineFailure",
                                    "severity": "critical",
                                    "pipeline": "${env.JOB_NAME}",
                                    "build_number": "${env.BUILD_NUMBER}",
                                    "environment": "production",
                                    "project": "terraform-ec2",
                                    "alert_type": "ci_cd"
                                },
                                "annotations": {
                                    "summary": "Jenkins Pipeline Failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                                    "description": "Pipeline ${env.JOB_NAME} failed at build #${env.BUILD_NUMBER}",
                                    "build_url": "${env.BUILD_URL}",
                                    "console_log": "${env.BUILD_URL}console",
                                    "triggered_by": "${env.BUILD_USER ?: 'auto'}",
                                    "duration": "${currentBuild.durationString}",
                                    "git_branch": "${env.GIT_BRANCH ?: 'N/A'}",
                                    "workspace": "${env.WORKSPACE}"
                                },
                                "startsAt": "${env.START_TIME}",
                                "endsAt": "${env.END_TIME}",
                                "generatorURL": "${env.BUILD_URL}",
                                "fingerprint": "jenkins_${env.JOB_NAME}_${env.BUILD_NUMBER}"
                            }
                        ],
                        "groupLabels": {
                            "alertname": "JenkinsPipelineFailure",
                            "pipeline": "${env.JOB_NAME}"
                        },
                        "commonLabels": {
                            "alertname": "JenkinsPipelineFailure",
                            "severity": "critical",
                            "alert_type": "ci_cd"
                        },
                        "commonAnnotations": {
                            "summary": "Jenkins Pipeline Failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                            "build_url": "${env.BUILD_URL}"
                        },
                        "externalURL": "${env.JENKINS_URL}",
                        "version": "4",
                        "groupKey": "{}:{alertname=\\"JenkinsPipelineFailure\\",pipeline=\\"${env.JOB_NAME}\\"}"
                    }
                    """
                            
                    sh """
                        curl -X POST '${ALERT_ENDPOINT}' \\
                            -H 'Content-Type: application/json' \\
                            -d '${payload}'
                    """
                } else {
                    echo "⚠ Alert suppressed - pipeline failure on branch: ${params.GIT_BRANCH} (alerts only sent for main branch)"
                }
            }
        }
    }
}
