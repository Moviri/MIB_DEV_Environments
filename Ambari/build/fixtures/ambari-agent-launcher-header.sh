#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific

# description: ambari-agent daemon
# processname: ambari-agent

# /etc/init.d/ambari-agent
set -u # fail on unset variables
VERSION="${ambariVersion}"
HASH="${buildNumber}"
_SCRIPT=$0

case "${1:-}" in
  --version)
        echo -e ${VERSION}
        exit 0
        ;;
  --hash)
        echo -e ${HASH}
        exit 0
        ;;
esac
