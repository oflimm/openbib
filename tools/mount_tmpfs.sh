#!/bin/bash

path=$1
size=$2

mount -t tmpfs -o size=${size} tmpfs $path