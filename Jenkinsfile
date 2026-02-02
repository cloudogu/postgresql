@Library([
  'pipe-build-lib',
  'ces-build-lib',
  'dogu-build-lib'
]) _

def pipe = new com.cloudogu.sos.pipebuildlib.DoguPipe(this, [
    doguName             : 'postgresql',
    shellScripts         : '''
                            resources/backup-consumer.sh
                            resources/create-sa.sh
                            resources/pre-upgrade.sh
                            resources/remove-sa.sh
                            resources/startup.sh
                            resources/upgrade-notification.sh
                            ''',
    doBatsTests          : false,
    checkMarkdown        : false,
    checkEOL             : false,
    dependencies         : ['usermgt', 'cas'],
])

pipe.setBuildProperties()
pipe.addDefaultStages()

pipe.insertStageAfter("verify", 'Finish Release')
{
        String releaseVersion = 'v14.17-6'
        pipe.ecoSystem.push('/dogu')
        pipe.github.createReleaseWithChangelog(releaseVersion, changelog, "main")
}

pipe.run()