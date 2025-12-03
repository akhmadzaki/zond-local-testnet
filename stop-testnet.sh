#!/bin/bash

ps aux | grep zond-testnet- | grep -v grep | awk '{print $2}' | xargs -r kill -9
ps aux | grep bin/bootnode | grep -v grep | awk '{print $2}' | xargs -r kill -9

sleep 1