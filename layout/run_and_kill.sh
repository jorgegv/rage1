#!/bin/bash

SLEEP=10

fuse --machine 128 --printer --textfile output.txt layout.tap &
sleep $SLEEP
kill -9 %1
