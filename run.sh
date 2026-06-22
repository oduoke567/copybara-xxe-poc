#!/bin/bash
rm -rf /tmp/dest-repo && git init --bare /tmp/dest-repo 2>/dev/null
java -jar /root/copybara/bazel-bin/java/com/google/copybara/copybara_deploy.jar migrate copy.bara.sky --force 2>&1
