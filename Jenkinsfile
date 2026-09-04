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
                            resources/post-upgrade.sh
                            resources/pre-upgrade.sh
                            resources/remove-sa.sh
                            resources/startup.sh
                            resources/upgrade-notification.sh
                            resources/util.sh
                            ''',
    doBatsTests          : true,
    checkMarkdown        : true,
    checkEOL             : false,
    dependencies         : ['usermgt', 'cas'],
    defaultBranch        : 'master',
])

pipe.setBuildProperties()
pipe.addDefaultStages()
pipe.run()