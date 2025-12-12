#!/bin/bash

#stop VC node
ps aux | grep beacon-rest-api-provider | grep -v grep | awk '{print $2}' | xargs -r kill -9
#stop CL node
ps aux | grep min-sync-peers | grep -v grep | awk '{print $2}' | xargs -r kill -9
#stop EL node
ps aux | grep authrpc.jwtsecret | grep -v grep | awk '{print $2}' | xargs -r kill -9

#stop EL bootnode
ps aux | grep nodekey=boot.key | grep -v grep | awk '{print $2}' | xargs -r kill -9

sleep 2