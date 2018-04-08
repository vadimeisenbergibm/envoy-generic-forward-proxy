#!/bin/bash

# Copyright IBM Corporation 2017,2018
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#based on https://github.com/istio/pilot/blob/master/docker/prepare_proxy.sh

set -o errexit
set -o nounset

ENVOY_PORT=$1
ENVOY_UID=$2
NGINX_MAIN_UID=$3
NGINX_WORKER_UID=$4

iptables -t nat -N ISTIO_REDIRECT
iptables -t nat -A ISTIO_REDIRECT -p tcp -j REDIRECT --to-port $ENVOY_PORT
iptables -t nat -A PREROUTING -j ISTIO_REDIRECT

iptables -t nat -N ISTIO_OUTPUT
iptables -t nat -A OUTPUT -p tcp -j ISTIO_OUTPUT
iptables -t nat -A ISTIO_OUTPUT -m owner --uid-owner ${ENVOY_UID} -j RETURN
iptables -t nat -A ISTIO_OUTPUT -m owner --uid-owner ${NGINX_MAIN_UID} -j RETURN
iptables -t nat -A ISTIO_OUTPUT -m owner --uid-owner ${NGINX_WORKER_UID} -j RETURN
iptables -t nat -A ISTIO_OUTPUT -j ISTIO_REDIRECT
