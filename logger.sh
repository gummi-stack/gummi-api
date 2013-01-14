#!/bin/bash


tee >(sed -u  "s/^/`date +%s000` 9a0f22fb-7f35-4f76-87dc-00c8b5776e7d /" | cat  > /dev/udp/10.11.1.93/7777) 
# tee >(sed -u  "s/^/`date +%s000` 9a0f22fb-7f35-4f76-87dc-00c8b5776e7d /" | netcat -q1 -u 10.11.1.93 7777) 

