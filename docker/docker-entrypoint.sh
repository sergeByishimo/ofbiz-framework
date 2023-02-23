#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
###############################################################################

###############################################################################
# OFBiz initialisation script for use as the entry point in a docker container.
#
# Triggers the loading of data and configuration of various OFBiz properties before
# executing the command given as arguments to the script.
#
# Behaviour controlled by environment variables:
#
# OFBIZ_SKIP_INIT
# Any non-empty value will cause this script to skip any initialisation steps.
# Default: <empty>
#
# OFBIZ_ADMIN_USER
# The username of the OFBIZ admin user.
# Default: admin
#
# OFBIZ_ADMIN_PASSWORD
# The password of the OFBIZ admin user.
# Default: ofbiz
#
# OFBIZ_DATA_LOAD
# Determine what type of data loading is required.
# Default: seed
# Values:
# - none: No data loading is performed.
# - seed: Seed data is loaded.
# - demo: Demo data is loaded.
#
# OFBIZ_HOST
# Specify the hostname used to access OFBiz.
# Used to populate the host-headers-allowed property in framework/security/config/security.properties.
# Default: localhost
#
# OFBIZ_CONTENT_URL_PREFIX
# Used to set the content.url.prefix.secure and content.url.prefix.standard properties in
# framework/webapp/config/url.properties.
# Default: https://${OFBIZ_HOST}
#
# OFBIZ_ENABLE_AJP_PORT
# Enable the AJP (Apache JServe Protocol) port to allow communication with OFBiz via a reverse proxy.
# Enabled when this environment variable contains a non-empty value.
# Default value: <empty>
#
# Hooks are executed at the various stages of the initialisation process by executing scripts in the following
# directories. Scripts must be executable and have the .sh extension:
#
# /docker-entrypoint-before-data-load.d
# Executed before any data loading is about to be performed. Only executed if data loading is required.
# Example usage would be to alter the data to be loaded.
#
# /docker-entrypoint-after-data-load.d
# Executed after any data loading has been performed. Only executed if data loading was required.
#
###############################################################################
set -x
set -e

trap shutdown_ofbiz SIGTERM SIGINT

CONTAINER_STATE_DIR="/ofbiz/runtime/container_state"
CONTAINER_DATA_LOADED="$CONTAINER_STATE_DIR/data_loaded"
CONTAINER_ADMIN_LOADED="$CONTAINER_STATE_DIR/admin_loaded"
CONTAINER_CONFIG_APPLIED="$CONTAINER_STATE_DIR/config_applied"

###############################################################################
# Validate and apply defaults to any environment variables used by this script.
# See script header for environment variable descriptions.
ofbiz_setup_env() {
  case "$OFBIZ_DATA_LOAD" in
  none | seed | demo) ;;
  *)
    OFBIZ_DATA_LOAD="none"
    ;;
  esac

  OFBIZ_ADMIN_USER=${OFBIZ_ADMIN_USER:-admin}

  OFBIZ_ADMIN_PASSWORD=${OFBIZ_ADMIN_PASSWORD:-ofbiz}

  OFBIZ_HOST=${OFBIZ_HOST:-localhost}

  OFBIZ_CONTENT_URL_PREFIX=${OFBIZ_CONTENT_URL_PREFIX:-https://${OFBIZ_HOST}}
}

###############################################################################
# Create the runtime container state directory used to track which initialisation
# steps have been run for the container.
# This directory should be hosted on a volume that persists for the life of the container.
create_ofbiz_runtime_directories() {
  if [ ! -d "$CONTAINER_STATE_DIR" ]; then
    mkdir --parents "$CONTAINER_STATE_DIR"
  fi
}

###############################################################################
# Execute the shell scripts at the paths passed to this function.
# Args:
# 1:  Name of the hook stage being executed. Used for logging.
# 2+: Variable number of paths to the shell scripts to be executed.
#     Only scripts with the .sh extension are executed.
#     Scripts will be sourced if they are not executable.
run_init_hooks() {
  local hookStage="$1"
  shift
  local filePath
  for filePath; do
    case "$filePath" in
    *.sh)
      if [ -x "$filePath" ]; then
        printf '%s: running %s\n' "$hookStage" "$filePath"
        "$filePath"
      else
        printf '%s: sourcing %s\n' "$hookStage" "$filePath"
        . "$filePath"
      fi
      ;;
    *)
      printf '%s: Not a script. Ignoring %s\n' "$hookStage" "$filePath"
      ;;
    esac
  done
}

###############################################################################
# If required, load data into OFBiz.
load_data() {
  if [ ! -f "$CONTAINER_DATA_LOADED" ]; then
    run_init_hooks /docker-entrypoint-before-data-load.d/*

    case "$OFBIZ_DATA_LOAD" in
    none) ;;

    seed)
      /ofbiz/bin/ofbiz --load-data readers=seed,seed-initial
      ;;

    demo)
      /ofbiz/bin/ofbiz --load-data
      # Demo data includes the admin user so indicate that the user is already loaded.
      touch "$CONTAINER_ADMIN_LOADED"
      ;;
    esac

    # Load any additional data files provided.
    if [ -z $(find /docker-entrypoint-additional-data.d/ -prune -empty) ]; then
      /ofbiz/bin/ofbiz --load-data dir=/docker-entrypoint-additional-data.d
    fi

    touch "$CONTAINER_DATA_LOADED"

    run_init_hooks /docker-entrypoint-after-data-load.d/*
  fi
}

###############################################################################
# Create and load the password hash for the admin user.
load_admin_user() {
  if [ ! -f "$CONTAINER_ADMIN_LOADED" ]; then
    TMPFILE=$(mktemp)

    # Concatenate a random salt and the admin password.
    SALT=$(tr --delete --complement A-Za-z0-9 </dev/urandom | head --bytes=16)
    SALT_AND_PASSWORD="${SALT}${OFBIZ_ADMIN_PASSWORD}"

    # Take a SHA-1 hash of the combined salt and password and strip off any additional output form the sha1sum utility.
    SHA1SUM_ASCII_HEX=$(printf "$SALT_AND_PASSWORD" | sha1sum | cut --delimiter=' ' --fields=1 --zero-terminated | tr --delete '\000')

    # Convert the ASCII Hex representation of the hash to raw bytes by inserting escape sequences and running
    # through the printf command. Encode the result as URL base 64 and remove padding.
    SHA1SUM_ESCAPED_STRING=$(printf "$SHA1SUM_ASCII_HEX" | sed -e 's/\(..\)\.\?/\\x\1/g')
    SHA1SUM_BASE64=$(printf "$SHA1SUM_ESCAPED_STRING" | basenc --base64url --wrap=0 | tr --delete '=')

    # Concatenate the hash type, salt and hash as the encoded password value.
    ENCODED_PASSWORD_HASH="\$SHA\$${SALT}\$${SHA1SUM_BASE64}"

    # Populate the login data template
    sed "s/@userLoginId@/$OFBIZ_ADMIN_USER/g; s/currentPassword=\".*\"/currentPassword=\"$ENCODED_PASSWORD_HASH\"/g;" framework/resources/templates/AdminUserLoginData.xml >"$TMPFILE"

    # Load data from the populated template.
    /ofbiz/bin/ofbiz --load-data "file=$TMPFILE"

    rm "$TMPFILE"

    touch "$CONTAINER_ADMIN_LOADED"
  fi
}

###############################################################################
# Apply any configuration changes required.
apply_configuration() {
  if [ ! -f "$CONTAINER_CONFIG_APPLIED" ]; then
    run_init_hooks /docker-entrypoint-before-config-applied.d/*

    if [ -n "$OFBIZ_ENABLE_AJP_PORT" ]; then
      # Configure tomcat to listen for AJP connections on all interfaces within the container.
      sed --in-place \
       '/<property name="ajp-connector" value="connector">/ a <property name="address" value="0.0.0.0"/>'  \
       /ofbiz/framework/catalina/ofbiz-component.xml
    fi

    sed --in-place \
     "s/host-headers-allowed=.*/host-headers-allowed=${OFBIZ_HOST}/" framework/security/config/security.properties

    sed --in-place \
     --expression="s#content.url.prefix.secure=.*#content.url.prefix.secure=${OFBIZ_CONTENT_URL_PREFIX}#;" \
     --expression="s#content.url.prefix.standard=.*#content.url.prefix.standard=${OFBIZ_CONTENT_URL_PREFIX}#;" \
     framework/webapp/config/url.properties

    touch "$CONTAINER_CONFIG_APPLIED"
    run_init_hooks /docker-entrypoint-after-config-applied.d/*
  fi
}

###############################################################################
# Send a shutdown signal to OFBiz
shutdown_ofbiz() {
  /ofbiz/send_ofbiz_stop_signal.sh
}

_main() {
  if [ -z "$OFBIZ_SKIP_INIT" ]; then
    ofbiz_setup_env
    create_ofbiz_runtime_directories
    apply_configuration
    load_data
    load_admin_user
  fi

  # Continue loading OFBiz.
  unset OFBIZ_SKIP_INIT
  unset OFBIZ_ADMIN_USER
  unset OFBIZ_ADMIN_PASSWORD
  unset OFBIZ_DATA_LOAD
  unset OFBIZ_ENABLE_AJP_PORT
  unset OFBIZ_HOST
  unset OFBIZ_CONTENT_URL_PREFIX
  exec "$@"
}

_main "$@"

