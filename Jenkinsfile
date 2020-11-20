#!groovy
@Library(['github.com/cloudogu/ces-build-lib@1.43.0', 'github.com/cloudogu/dogu-build-lib@v1.1.0', 'github.com/cloudogu/zalenium-build-lib@30923630ced3089ae0861bef25b60903429841aa'])
import com.cloudogu.ces.cesbuildlib.*
import com.cloudogu.ces.dogubuildlib.*
import com.cloudogu.ces.zaleniumbuildlib.*

node('docker') {
        stage('Checkout') {
            checkout scm
        }

        stage('Lint') {
            lintDockerfile()
            shellCheck('resources/backup-consumer.sh resources/create-sa.sh resources/pre-upgrade.sh resources/startup.sh')
        }
}

node('vagrant') {

    Git git = new Git(this, 'cesmarvin')
    git.committerName = 'cesmarvin'
    git.committerEmail = 'cesmarvin@cloudogu.com'
    String doguDirectory = '/dogu'

    timestamps {
        properties([
            // Keep only the last x builds to preserve space
            buildDiscarder(logRotator(numToKeepStr: '10')),
            // Don't run concurrent builds for a branch, because they use the same workspace directory
            disableConcurrentBuilds()
        ])

        EcoSystem ecoSystem = new EcoSystem(this, 'gcloud-ces-operations-internal-packer', 'jenkins-gcloud-ces-operations-internal')

        try {
            stage('Provision') {
                ecoSystem.provision(doguDirectory)
            }

            stage('Setup') {
                ecoSystem.loginBackend('cesmarvin-setup')
                ecoSystem.setup()
            }

            stage('Wait for dependencies') {
                timeout(15) {
                    ecoSystem.waitForDogu('cas')
                    ecoSystem.waitForDogu('usermgt')
                }
            }

            stage('Build') {
                ecoSystem.build(doguDirectory)
            }

            stage('Verify') {
                ecoSystem.verify(doguDirectory)
            }

        } finally {
            stage('Clean') {
                ecoSystem.destroy()
            }
        }
    }
}
