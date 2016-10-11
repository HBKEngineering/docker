FROM java:8-jdk

RUN apt-get update && apt-get install -y apt-utils
RUN apt-get install -y ruby2.1 ruby2.1-dev
RUN apt-get update && apt-get install -y git python-pip curl zip gzip build-essential rubygems rubygems-integration && rm -rf /var/lib/apt/lists/*
RUN pip install awscli
RUN pip install awsebcli
RUN L=/usr/local/bin/flynn && curl -sSL -A "`uname -sp`" https://dl.flynn.io/cli | zcat >$L && chmod +x $L
RUN gem install sass

RUN wget https://get.docker.com/builds/Linux/x86_64/docker-1.12.1.tgz
RUN tar -xvzf docker-1.12.1.tgz
RUN cp docker/docker /usr/local/bin/docker
ENV DOCKER_CERT_PATH /var/docker-keys

RUN wget https://github.com/rancher/rancher-compose/releases/download/v0.9.2/rancher-compose-linux-amd64-v0.9.2.tar.gz
RUN gunzip rancher-compose-linux-amd64-v0.9.2.tar.gz
RUN tar -xvf rancher-compose-linux-amd64-v0.9.2.tar
RUN cp rancher-compose-v0.9.2/rancher-compose /usr/local/bin/rancher-compose

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_SLAVE_AGENT_PORT 6000
ENV JENKINS_OPTS '--httpPort=5000'

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000


# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container, 
# ensure you use the same uid
RUN groupadd -g ${gid} ${group} \
    && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}

RUN chmod 777 -R /tmp && chmod o+t -R /tmp

# Jenkins home directory is a volume, so configuration and build history 
# can be persisted and survive image upgrades
VOLUME /var/jenkins_home

# Add another volume for injecting docker certificates
VOLUME /var/docker-keys

# `/usr/share/jenkins/ref/` contains all reference configuration we want 
# to set on a fresh new installation. Use it to bundle additional plugins 
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d

ENV TINI_SHA 066ad710107dc7ee05d3aa6e4974f01dc98f3888

# Use tini as subreaper in Docker container to adopt zombie processes 
RUN curl -fsSL https://github.com/krallin/tini/releases/download/v0.5.0/tini-static -o /bin/tini && chmod +x /bin/tini \
  && echo "$TINI_SHA  /bin/tini" | sha1sum -c -

COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy

ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.14}
ARG JENKINS_SHA
ENV JENKINS_SHA ${JENKINS_SHA:-ab6b981979052880f1e34189cb38d9ed4fdf0670}


# could use ADD but this one does not check Last-Modified header 
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL http://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war -o /usr/share/jenkins/jenkins.war \
  && echo "$JENKINS_SHA  /usr/share/jenkins/jenkins.war" | sha1sum -c -

ENV JENKINS_UC https://updates.jenkins.io
RUN chown -R ${user} "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
# EXPOSE 8080

# will be used by attached slave agents:
#EXPOSE 50000

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

#ADD nginx.conf.sigil /app/
#RUN chown -R ${user} /app

USER ${user}

COPY jenkins.sh /usr/local/bin/jenkins.sh
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
