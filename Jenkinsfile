/*
 * This pipeline supports only `minor` releases. Don't run it on `major`, `patch`,
 * `snapshot`, nor `edge` releases.
 *
 * The Jenkins job should be configured with the following properties:
 *
 * - Disable concurrent builds
 * - Parameters (all must be trimmed; all are strings):
 *    - RELEASE_TYPE
 *      defaultValue: minor
 *      description: Valid values are: minor.
 *   - OPERATOR_REPO
 *      defaultValue: kiali/kiali-operator
 *      description: The GitHub repo of the kiali-operator sources, in owner/repo format.
 *   - OPERATOR_RELEASING_BRANCH
 *      defaultValue: refs/heads/master
 *      description: Branch of the kiali-operator repo to checkout and run the release
 *   - QUAY_OPERATOR_NAME
 *      defaultValue: quay.io/kiali/kiali-operator
 *      description: The name of the Quay repository to push the operator release
 */

def bumpVersion(String versionType, String currentVersion) {
  def split = currentVersion.split('\\.')
    switch (versionType){
      case "patch":
        split[2]=1+Integer.parseInt(split[2])
          break
      case "minor":
          split[1]=1+Integer.parseInt(split[1])
          split[2]=0
            break;
      case "major":
          split[0]=1+Integer.parseInt(split[0])
          split[1]=0
          split[2]=0
            break;
    }
  return split.join('.')
}

node('kiali-build && fedora') {
  def operatorGitUri = "git@github.com:${params.OPERATOR_REPO}.git"
  def operatorPullUri = "https://api.github.com/repos/${params.OPERATOR_REPO}/pulls"
  def operatorReleaseUri = "https://api.github.com/repos/${params.OPERATOR_REPO}/releases"
  def forkGitUri = "git@github.com:kiali-bot/kiali-operator.git"
  def mainBranch = 'master'

  try {
    stage('Checkout code') {
      checkout([
          $class: 'GitSCM',
          branches: [[name: params.OPERATOR_RELEASING_BRANCH]],
          doGenerateSubmoduleConfigurations: false,
          extensions: [
          [$class: 'LocalBranch', localBranch: '**']
          ],
          submoduleCfg: [],
          userRemoteConfigs: [[
          credentialsId: 'kiali-bot-gh-ssh',
          url: operatorGitUri]]
      ])

      sh "git config user.email 'kiali-dev@googlegroups.com'"
      sh "git config user.name 'kiali-bot'"
    }

    if (env.OPERATOR_FORK_URI) {
      forkGitUri = env.OPERATOR_FORK_URI
    } else if (params.OPERATOR_REPO != 'kiali/kiali-operator') {
      // This allows to test the pipeline against a personal repository
      forkGitUri = sh(
          returnStdout: true,
          script: "git config --get remote.origin.url").trim()
    } 
    def kialiBotUser = (forkGitUri =~ /.+:(.+)\/.+/)[0][1]

    def releasingVersion = ""
    def nextVersion = ""
    def versionBranch = ""
    def containerTag = ""


    stage('Build Operator') {
      // Resolve the version to release and calculate next version
      releasingVersion = sh(
          returnStdout: true,
          script: "sed -rn 's/^VERSION \\?= v(.*)/\\1/p' Makefile").trim().replace("-SNAPSHOT", "")
      nextVersion = bumpVersion("minor", releasingVersion)

      if (params.RELEASE_TYPE == "patch") {
        releasingVersion = bumpVersion(params.RELEASE_TYPE, releasingVersion)
        nextVersion = bumpVersion(params.RELEASE_TYPE, releasingVersion)
      }

      if (params.RELEASE_TYPE.contains("snapshot")) {
        releasingVersion = releasingVersion + params.RELEASE_TYPE
        containerTag = "v${releasingVersion}"
      } else if (params.RELEASE_TYPE == "edge") {
        releasingVersion = "latest"
        containerTag = "latest"
      } else {
        versionBranch = "v" + releasingVersion.replaceFirst(/\.\d+$/, "")
        containerTag = "v${releasingVersion}"
      }

      // Build
      echo "Will build version: ${containerTag} "
      echo "Will create/update branch tags: ${versionBranch}"
      echo "Next version: ${nextVersion}"
      sh "sed -i -r 's/^VERSION \\?= v.*/VERSION \\?= ${containerTag}/' Makefile"
      sh "OPERATOR_QUAY_NAME=\"${params.QUAY_OPERATOR_NAME}\" make clean build"
    }

    stage('Release Kiali Operator to Container Repositories') {
      withCredentials([usernamePassword(credentialsId: 'kiali-quay', passwordVariable: 'QUAY_PASSWORD', usernameVariable: 'QUAY_USER')]) {
        def quayOperatorTag = "${params.QUAY_OPERATOR_NAME}:${containerTag}"
        if (params.RELEASE_TYPE != 'edge' && !params.RELEASE_TYPE.contains("snapshot")) {
          quayOperatorTag = quayOperatorTag + " ${params.QUAY_OPERATOR_NAME}:${versionBranch}"
        }

	echo "Logging in to Quay.io..."
	sh """
          docker login -u "\$QUAY_USER" -p "\$QUAY_PASSWORD" quay.io
          OPERATOR_QUAY_TAG="${quayOperatorTag}" make -e DOCKER_CLI_EXPERIMENTAL=enabled container-multi-arch-push-kiali-operator-quay
        """
      }
    }

    stage('Create release cut in operator repo') {
      withCredentials([string(credentialsId: 'kiali-bot-gh-token', variable: 'GH_TOKEN')]) {
        sshagent(['kiali-bot-gh-ssh']) {
          //sh "make -f ${operatorMakefile} -C ${operatorDir} operator-push-version-tag operator-prepare-next-version"

          // Create git tags for the released version
          if (params.RELEASE_TYPE != 'edge') {
            echo "Creating git tag ${containerTag}"
            sh """
              git add Makefile
              git commit -m "Release ${releasingVersion}"
              git push origin \$(git rev-parse HEAD):refs/tags/${containerTag}
            """

            def prerelease = 'false'
            if (params.RELEASE_TYPE.contains('snapshot')) {
              prerelease = 'true'
            }

            echo "Creating GitHub release entry for ${containerTag}"
            sh """
              curl -H "Authorization: token \$GH_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{"name": "Kiali Operator ${releasingVersion}", "tag_name": "${containerTag}", "prerelease": ${prerelease}}' \
                -X POST ${operatorReleaseUri}
            """
          } else {
            echo "Edge release is not tagged in GitHub"
          }

          // Create/update a branch that we can use for a patch release, in case it's needed
          if (params.RELEASE_TYPE != 'edge' && !params.RELEASE_TYPE.contains('snapshot')) {
	    sh "git push origin \$(git rev-parse HEAD):refs/heads/${versionBranch}"
          }

          // Create PR to prepare master branch for next version (required only in minor versions)
          if (params.RELEASE_TYPE == "minor") {
            echo "Creating PR to prepare for version ${nextVersion}"
            sh """
              sed -i -r "s/^VERSION \\?= (.*)/VERSION \\?= v${nextVersion}-SNAPSHOT/" Makefile
              git add Makefile
              git commit -m "Prepare for next version"
	      git push ${forkGitUri} \$(git rev-parse HEAD):refs/heads/${BUILD_TAG}-main
	      curl -H "Authorization: token $GH_TOKEN" \
	        -H "Content-Type: application/json" \
	        -d '{"title": "Prepare for next version", "body": "Please, merge to update version numbers and prepare for release ${nextVersion}.", "head": "${kialiBotUser}:${BUILD_TAG}-main", "base": "${mainBranch}"}' \
	        -X POST ${operatorPullUri}
            """
          }
        }
      }
    }
  } finally {
    cleanWs()
  }
}
