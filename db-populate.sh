#! /bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# OpenCRVS is also distributed under the terms of the Civil Registration
# & Healthcare Disclaimer located at http://opencrvs.org/license.
#
# Copyright (C) The OpenCRVS Authors. OpenCRVS and the OpenCRVS
# graphic logo are (registered/a) trademark(s) of Plan International.
set -e

print_usage_and_exit () {
    echo 'Usage: ./db-populate.sh --password_for_users=XXX --environment=development|production --alpha3_country_code=XXX --path_to_admin_structure_csv=XXX --path_to_crvs_offices_csv=XXX --path_to_health_facilities_csv=XXX --path_to_statistics_csv=XXX --path_to_employees_csv=XXX'
    echo "  --password_for_users will be the password and security question answer for all users used in development."
    echo "    The --password_for_users property is ignored if populating production users in bulk."
    echo "    In production, first time use passwords will be dynamically generated by this script."
    echo "  --environment must have a value of 'development' or 'production' set e.g. --environment=developmemt"
    echo "  --alpha3_country_code must have a value equal to an alpha3 country code.  Such as BGD for Bangladesh"
    echo "    Alpha 3 ISO country codes can be found at: https://www.iban.com/country-codes"
    exit 1
}

for i in "$@"; do
  case $i in
    --environment=*)
      environment="${i#*=}"
      shift
      ;;
    --password_for_users=*)
      password_for_users="${i#*=}"
      shift
      ;;
    --alpha3_country_code=*)
      alpha3_country_code="${i#*=}"
      shift
      ;;
    --path_to_admin_structure_csv=*)
      path_to_admin_structure_csv="${i#*=}"
      shift
      ;;
    --path_to_statistics_csv=*)
      path_to_statistics_csv="${i#*=}"
      shift
      ;;
    --path_to_crvs_offices_csv=*)
      path_to_crvs_offices_csv="${i#*=}"
      shift
      ;;
    --path_to_health_facilities_csv=*)
      path_to_health_facilities_csv="${i#*=}"
      shift
      ;;
    --path_to_employees_csv=*)
      path_to_employees_csv="${i#*=}"
      shift
      ;;
    -*|--*)
      echo "Unknown option $i"
      exit 1
      ;;
    *)
      ;;
  esac
done

# Retrieve 2-step verification to continue
#-----------------------------------------
ask_yes_or_no() {
    read -p "$1 ([y]es or [N]o): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

if [ -z $environment ] || { [ $environment != 'development' ] && [ $environment != 'production' ] ;} ; then
    echo "MISSING OR INCORRECT PARAMETER: --environment"
    echo
    print_usage_and_exit
elif [ -z $password_for_users ] && [ $environment == 'development' ] ; then
    echo "FOR DEVELOPMENT, PASSWORD IS REQUIRED"
    echo
    print_usage_and_exit
elif [ -z $alpha3_country_code ]; then
    echo "MISSING OR INCORRECT PARAMETER: --alpha3_country_code"
    echo
    print_usage_and_exit
elif [ -z $path_to_admin_structure_csv ]; then
    echo "MISSING OR INCORRECT PARAMETER: --path_to_admin_structure_csv"
    echo
    print_usage_and_exit
elif [ -z $path_to_crvs_offices_csv ]; then
    echo "MISSING OR INCORRECT PARAMETER: --path_to_crvs_offices_csv"
    echo
    print_usage_and_exit
elif [ -z $path_to_health_facilities_csv ]; then
    echo "MISSING OR INCORRECT PARAMETER: --path_to_health_facilities_csv"
    echo
    print_usage_and_exit
elif [ -z $path_to_employees_csv ]; then
    echo "MISSING OR INCORRECT PARAMETER: --path_to_employees_csv"
    echo
    print_usage_and_exit
elif [ -z $path_to_statistics_csv ]; then
    echo "MISSING OR INCORRECT PARAMETER: --path_to_statistics_csv"
    echo
    echo "STATISTICS CSV HAS NOT BEEN SUPPLIED.  Do you wish to proceed without statistics?"
    echo
    echo "Please note that the Performance Dashboard will be unable to calculate Registration Completeness Rates without statistics."
    echo
    if [[ "no" == $(ask_yes_or_no "If you are ready to continue, type: yes.  If you dont know, type: no to exit.") ]]
    then
        echo -e "\n\nExiting."
        exit 0
    fi
elif [ -z $password_for_users ] && [ $environment == 'production' ] ; then
    echo "PROCEEDING TO POPULATE DATABASE WITH BULK USERS IN PRODUCTION."
    echo
    echo "FIRST TIME PASSWORDS FOR THESE USERS WILL OUTPUT AT THE END OF THIS SCRIPT FOR ONE TIME USE ONLY"
    echo
    sleep 5
fi

echo "\$environment: '$environment' \$password_for_users: '$password_for_users' \$alpha3_country_code: '$alpha3_country_code'"

# Clear existing application data

HOST=mongo1
NETWORK=opencrvs_default

docker run --rm --network=$NETWORK mongo:4.4 mongo hearth-dev --host $HOST --eval "db.dropDatabase()"
docker run --rm --network=$NETWORK mongo:4.4 mongo user-mgnt --host $HOST --eval "db.dropDatabase()"
docker run --rm --network=$NETWORK mongo:4.4 mongo application-config --host $HOST --eval "db.dropDatabase()"
docker run --rm --network=$NETWORK mongo:4.4 mongo metrics --host $HOST --eval "db.dropDatabase()"
docker run --rm --network=$NETWORK mongo:4.4 mongo reports --host $HOST --eval "db.dropDatabase()"
docker run --rm --network=$NETWORK mongo:4.4 mongo config --host $HOST --eval "db.dropDatabase()"
docker run --rm --network=$NETWORK mongo:4.4 mongo webhooks --host $HOST --eval "db.dropDatabase()"
docker run --rm --network=$NETWORK appropriate/curl curl -XDELETE 'http://opensearch:9200/*' -v
docker run --rm --network=$NETWORK appropriate/curl curl -X POST 'http://influxdb:8086/query?db=ocrvs' --data-urlencode "q=DROP SERIES FROM /.*/" -v

# Populate new application data
ts-node -r tsconfig-paths/register src/scripts/validate-source-files.ts -- $path_to_admin_structure_csv $path_to_crvs_offices_csv $path_to_health_facilities_csv $path_to_employees_csv $path_to_statistics_csv
ts-node -r tsconfig-paths/register src/features/administrative/scripts/import-default-config-and-admin-structure.ts -- $path_to_admin_structure_csv
ts-node -r tsconfig-paths/register src/features/facilities/scripts/import-offices-and-health-facilities.ts -- $path_to_crvs_offices_csv $path_to_health_facilities_csv
ts-node -r tsconfig-paths/register src/features/administrative/scripts/import-statistics.ts -- $path_to_statistics_csv $path_to_admin_structure_csv
ts-node -r tsconfig-paths/register src/features/employees/scripts/import-employees.ts -- $path_to_employees_csv $password_for_users $environment $alpha3_country_code
