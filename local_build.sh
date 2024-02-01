#!/bin/sh

# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

ORIGIN=`pwd`
BUILD=$ORIGIN/build

# date stamp for this deploy
STAMP=`date +%s`
echo build stamp is $STAMP

# Parse params for packaging code (Lambda Layer + Bucket Name Params)
for PARAM in "$@"
do
   KEY=$(echo $PARAM | cut -f1 -d=)
   VALUE=$(echo $PARAM | cut -f2 -d=)
   if [ "$KEY" != "$VALUE" ];
   then
    export "$KEY"="$VALUE"
   fi
done

if [ ! "$BUCKET_NAME" ]; then
    echo "Error: Missing CLI arguement - Please specify BUCKET_NAME"
    exit 1
fi

echo "REQUIRES_SPEKE_SERVER_LAMBDA_LAYER = $REQUIRES_SPEKE_SERVER_LAMBDA_LAYER"
echo "BUCKET_NAME = $BUCKET_NAME"

# create a build folder
mkdir $BUILD

# clear the build folder
rm -f $BUILD/*

# create the reference server zip with a unique name
SERVZIP=speke-reference-lambda-$STAMP.zip
cd $ORIGIN/src

# create a lambda layer zip with a unique name if required
# - https://github.com/awslabs/speke-reference-server#sidenote-building-the-lambda-on-macwindows
# - https://aws.amazon.com/premiumsupport/knowledge-center/lambda-layer-simulated-docker/
if [ "${REQUIRES_SPEKE_SERVER_LAMBDA_LAYER}" = "true" ]; then
    
    # using zappa for help in packaging
    # if you're building using lambda layer then we need to exclude libs from the layer (cffi & cryptography)
    zappa package ossmac --output $BUILD/$SERVZIP

    cd $ORIGIN/lambda/speke_libs
    docker run \
        -v "$PWD":/var/task \
        --platform linux/amd64 \
        "public.ecr.aws/sam/build-python3.9" \
        /bin/sh -c "pip install -qq -r requirements.txt -t python/lib/python3.9/site-packages/ -U; exit"
    zip -r $BUILD/speke-libs-$STAMP.zip python > /dev/null
else
    # using zappa for help in packaging (no Lambda Layer required)
    zappa package oss --output $BUILD/$SERVZIP
fi

# create the custom resource zip with a unique name
RESZIP=cloudformation-resources-$STAMP.zip
cd $ORIGIN/cloudformation
zip -r $BUILD/$RESZIP mediapackage_endpoint_common.py mediapackage_speke_endpoint.py resource_tools.py

# update templates with the new zip filenames
sed -e "s/DEV_0_0_0/$STAMP/g ; s/BUILD_BUCKET_NAME/$BUCKET_NAME/g" speke_reference.json >$BUILD/speke_reference.json
sed -e "s/DEV_0_0_0/$STAMP/g" mediapackage_speke_endpoint.json >$BUILD/mediapackage_speke_endpoint.json

cd $BUILD

