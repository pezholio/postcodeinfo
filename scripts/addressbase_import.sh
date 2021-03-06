#!/bin/bash

OFFLINE_TABLE_NAME='postcode_api_address_offline'
PREV_LIVE_TABLE_NAME='postcode_api_address_prev_live'
TEMP_TABLE_NAME='tmp_addressbase_import'
LIVE_TABLE_NAME='postcode_api_address'

#: EPSG projection codes
BRITISH_NATIONAL_GRID=27700
WGS84=4326

# bring in general-purpose functions
source `dirname $0`/offline_table_import_functions.sh

function create_tmp_table_sql {
  echo "
    DROP TABLE IF EXISTS $TEMP_TABLE_NAME;

    -- UPRN is unquoted in the import, hence it has to be a bigint here
    CREATE UNLOGGED TABLE $TEMP_TABLE_NAME ( 
      UPRN bigint, 
      OS_ADDRESS_TOID varchar(40), 
      RM_UDPRN integer, 
      ORGANISATION_NAME varchar(120), 
      DEPARTMENT_NAME varchar(120), 
      PO_BOX_NUMBER varchar(12), 
      SUB_BUILDING_NAME varchar(60), 
      BUILDING_NAME varchar(100), 
      BUILDING_NUMBER integer, 
      DEPENDENT_THOROUGHFARE_NAME varchar(160), 
      THOROUGHFARE_NAME varchar(160), 
      POST_TOWN varchar(60), 
      DOUBLE_DEPENDENT_LOCALITY varchar(70), 
      DEPENDENT_LOCALITY varchar(70), 
      POSTCODE varchar(16), 
      POSTCODE_TYPE char(2), 
      X_COORDINATE float, 
      Y_COORDINATE float,
      LATITUDE float,
      LONGITUDE float,
      RPC integer,
      COUNTRY char(3),
      CHANGE_TYPE char(2), 
      LA_START_DATE date, 
      RM_START_DATE date,
      LAST_UPDATE_DATE date, 
      CLASS char(2)
    );
  "
}


# yes, get rid of anything from the live table, we're only doing full imports here
function convert_data_sql {
  echo "
    DROP TABLE IF EXISTS $OFFLINE_TABLE_NAME;

    SELECT 'creating offline table' AS status;
    CREATE TABLE $OFFLINE_TABLE_NAME AS 
      SELECT * from $LIVE_TABLE_NAME LIMIT 1;
    TRUNCATE TABLE $OFFLINE_TABLE_NAME;

    SELECT 'converting import data into offline address table' AS status;
    INSERT INTO $OFFLINE_TABLE_NAME
    (
      uprn,
      os_address_toid,
      rm_udprn,
      organisation_name,
      department_name,
      po_box_number,
      building_name,
      sub_building_name,
      building_number,
      dependent_thoroughfare_name,
      thoroughfare_name,
      post_town,
      double_dependent_locality,
      dependent_locality,
      point,
      postcode,
      postcode_index,
      postcode_type,
      rpc,
      change_type,
      start_date,
      last_update_date,
      primary_class,
      postcode_area
    ) SELECT 
      cast(UPRN AS varchar(12)),
      OS_ADDRESS_TOID, 
      RM_UDPRN, 
      ORGANISATION_NAME, 
      DEPARTMENT_NAME, 
      COALESCE(PO_BOX_NUMBER, ''), 
      BUILDING_NAME, 
      SUB_BUILDING_NAME, 
      BUILDING_NUMBER, 
      DEPENDENT_THOROUGHFARE_NAME, 
      THOROUGHFARE_NAME, 
      POST_TOWN, 
      DOUBLE_DEPENDENT_LOCALITY, 
      DEPENDENT_LOCALITY, 
      ST_SetSRID(ST_MakePoint(LONGITUDE, LATITUDE), $WGS84),
      POSTCODE, 
      lower(regexp_replace(POSTCODE, ' ', '')),
      POSTCODE_TYPE, 
      RPC, 
      CHANGE_TYPE, 
      RM_START_DATE, 
      LAST_UPDATE_DATE, 
      CLASS, 
      lower(split_part(POSTCODE, ' ', 1))
    FROM $TEMP_TABLE_NAME
    WHERE lower(CHANGE_TYPE) != 'D';

    TRUNCATE TABLE $TEMP_TABLE_NAME;
  "
}


function cleanup_tables_sql {
    for first_char in {a..z} {0..9}
    do
      echo "SELECT 'deleting from ${LIVE_TABLE_NAME}_${first_char}' AS status;"
      echo "TRUNCATE TABLE ${LIVE_TABLE_NAME}_${first_char};"
      echo "SELECT 'inserting into ${LIVE_TABLE_NAME}_${first_char}' AS status;"
      echo "INSERT INTO ${LIVE_TABLE_NAME}_${first_char}
            SELECT * FROM $OFFLINE_TABLE_NAME
            WHERE postcode_index LIKE '$first_char%';"
    done
}

# Main processing actually starts here
if [ $# -eq 0 ]
  then 
    echo "No arguments supplied"
    exit 1
else
  run_import "$@"
fi



