#!/bin/bash

set -ex -o xtrace

./bootstrap

xcodebuild -target OpenSCTokenApp -configuration Release -project OpenSCTokenApp.xcodeproj install DSTROOT=${PWD}/build
