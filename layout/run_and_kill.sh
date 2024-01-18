#!/bin/bash

fuse --machine 128 --printer --textfile output.txt layout.tap &
sleep 2
kill -9 %1
