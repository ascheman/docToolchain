FROM openjdk:17-jdk-bullseye

RUN apt-get update && apt-get install -y graphviz shellcheck
