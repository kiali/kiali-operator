# A one-time use script that converts all the operator versions in a directory to the new bundle format

set -eu

if ! which opm &>/dev/null ; then
  echo "You must have 'opm' in your PATH"
  exit 1
fi

if [ -d /tmp/operator-bundle ]; then
  echo "There appears to already be previously converted bundles in '/tmp/operator-bundle'. Please delete that directory."
  exit 1
fi

OP_DIR="${1:-doesnotexist}"
if [ ! -d ${OP_DIR} ]; then
  echo "Pass in a directory that contains an operator package manifest"
  exit 1
fi

# get the absolute path
OP_DIR="$(cd ${OP_DIR} && pwd)"

if ! ls ${OP_DIR}/*.package.yaml &>/dev/null ; then
  echo "The directory you passed in does not contain operator metadata: ${OP_DIR}"
  exit 1
else
  echo "Will convert the metadata for the operator found here: ${OP_DIR}"
fi

VERSIONS=$(cd ${OP_DIR} && ls -1d * | grep -v package.yaml | sort -V)
echo "Number of versions that will be converted: $(echo ${VERSIONS} | wc -w)"

for v in ${VERSIONS}
do
  echo "Converting: ${v}"
  mkdir -p /tmp/operator-bundle/${v}
  pushd /tmp/operator-bundle/${v}
  opm alpha bundle build --directory ${OP_DIR}/${v}/ --tag opbundle:tmp --output-dir .
  popd
done

echo "The new bundles are located here: /tmp/operator-bundle"
ls /tmp/operator-bundle
