#!/bin/bash -x -e

echo "========================================"
echo "Hail on AWS EMR - Cluster Deployment"
echo "EMR 7.x with Spark 3.5.x"
echo "========================================"
echo ""
echo "See log details at /tmp/cloudcreation_log.out"

# Save the AWS Keys to the default folder
CREDENTIALS=$(ls ~/.aws 2>/dev/null)
if [ -z "$CREDENTIALS" ]; then
	echo "Your AWS configuration file is required!"
	echo "For help visit:"
	echo "https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html"
	echo "See your accessKeys.csv file to find the Access Keys"
	echo ""
	echo "Your inputs should look like this:"
	echo ""
	echo "AWS Access Key ID [None]: ANEXAMPLEKEYID"
	echo "AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
	echo "Default region name [None]: ap-southeast-1"
	echo "Default output format [None]: json"
	echo ""
	aws configure
else
	echo "Using existing AWS credentials..."
	echo "To reconfigure run: aws configure"
	echo "For help visit: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html"
	echo ""
fi


echo "Starting EMR 7.x cluster. This operation takes 10-15 minutes..."
python3 EMR_deploy_and_install_spot.py
