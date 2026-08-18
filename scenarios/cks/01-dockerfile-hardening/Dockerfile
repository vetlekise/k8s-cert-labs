# This Dockerfile ships with several security best-practice problems. Your task
# (see questions/cks.md #1) is to fix the TWO most prominent security issues
# WITHOUT changing what the image does. This is a local file exercise: there is
# no `task setup` for it.
FROM ubuntu:latest

RUN apt-get update -y
RUN apt-get install nginx -y

COPY entrypoint.sh /

ENTRYPOINT ["/entrypoint.sh"]

USER root
