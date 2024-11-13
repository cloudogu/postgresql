#!groovy
@Library(['github.com/cloudogu/ces-build-lib@2.2.1', 'github.com/cloudogu/dogu-build-lib@v2.5.0'])
import com.cloudogu.ces.cesbuildlib.*
import com.cloudogu.ces.dogubuildlib.*

node('docker') {
        stage('Checkout') {
            checkout scm
        }

        stage('Lint') {
            lintDockerfile()
            shellCheck('resources/backup-consumer.sh resources/create-sa.sh resources/pre-upgrade.sh resources/remove-sa.sh resources/startup.sh resources/upgrade-notification.sh')
        }

        stage('Check Markdown Links') {
            Markdown markdown = new Markdown(this, "3.12.2")
            markdown.check()
        }

        stage('Bats Tests') {
            Bats bats = new Bats(this, docker)
            bats.checkAndExecuteTests()
        }
}

node('vagrant') {

    String doguName = 'postgresql'
    Git git = new Git(this, 'cesmarvin')
    git.committerName = 'cesmarvin'
    git.committerEmail = 'cesmarvin@cloudogu.com'
    String doguDirectory = '/dogu'
    GitFlow gitflow = new GitFlow(this, git)
    GitHub github = new GitHub(this, git)
    Changelog changelog = new Changelog(this)

    timestamps {
        properties([
            // Keep only the last x builds to preserve space
            buildDiscarder(logRotator(numToKeepStr: '10')),
            // Don't run concurrent builds for a branch, because they use the same workspace directory
            disableConcurrentBuilds(),
            // Parameter to activate dogu upgrade test on demand
            parameters([
                    booleanParam(defaultValue: false, description: 'Test dogu upgrade from latest release or optionally from defined version below', name: 'TestDoguUpgrade'),
                    string(defaultValue: '', description: 'Old Dogu version for the upgrade test (optional; e.g. 4.1.0-3)', name: 'OldDoguVersionForUpgradeTest'),
            ])
        ])

        EcoSystem ecoSystem = new EcoSystem(this, 'gcloud-ces-operations-internal-packer', 'jenkins-gcloud-ces-operations-internal')
        Trivy trivy = new Trivy(this, ecoSystem)

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

            stage('Trivy scan') {
                trivy.scanDogu("/dogu", TrivyScanFormat.HTML, TrivyScanLevel.CRITICAL, TrivyScanStrategy.UNSTABLE)
                trivy.scanDogu("/dogu", TrivyScanFormat.JSON, TrivyScanLevel.CRITICAL, TrivyScanStrategy.UNSTABLE)
                trivy.scanDogu("/dogu", TrivyScanFormat.PLAIN, TrivyScanLevel.CRITICAL, TrivyScanStrategy.UNSTABLE)
            }

            stage('Verify') {
                ecoSystem.verify(doguDirectory)
            }

            if (params.TestDoguUpgrade != null && params.TestDoguUpgrade){
                stage('Upgrade dogu'){
                    ecoSystem.upgradeFromPreviousRelease(params.OldDoguVersionForUpgradeTest, doguName)
                }

                stage('Verify - after upgrade') {
                    ecoSystem.verify(doguDirectory)
                }
            }

            if (gitflow.isReleaseBranch()) {
                String releaseVersion = git.getSimpleBranchName()

                stage('Finish Release') {
                    gitflow.finishRelease(releaseVersion)
                }

                stage('Push Dogu to registry') {
                    ecoSystem.push(doguDirectory)
                }

                stage ('Add Github-Release') {
                    github.createReleaseWithChangelog(releaseVersion, changelog)
                }
            }

        } finally {
            stage('Clean') {
                ecoSystem.destroy()
            }
        }
    }
}
