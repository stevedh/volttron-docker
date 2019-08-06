ARG image_user=amd64
ARG image_repo=debian
ARG image_tag=buster

FROM ${image_user}/${image_repo}:${image_tag} as volttron_base

SHELL [ "bash", "-c" ]

ENV OS_TYPE=debian
ENV DIST=buster
ENV VOLTTRON_GIT_BRANCH=rabbitmq-volttron
ENV VOLTTRON_USER_HOME=/home/volttron
ENV VOLTTRON_HOME=${VOLTTRON_USER_HOME}/.volttron
ENV CODE_ROOT=/code
ENV VOLTTRON_ROOT=${CODE_ROOT}/volttron
ENV VOLTTRON_USER=volttron
ENV USER_PIP_BIN=${VOLTTRON_USER_HOME}/.local/bin
ENV RMQ_ROOT=${VOLTTRON_USER_HOME}/rabbitmq_server
ENV RMQ_HOME=${RMQ_ROOT}/rabbitmq_server-3.7.7

# --no-install-recommends \
RUN set -eux; apt-get update; apt-get install -y --no-install-recommends \
    procps \
    gosu \
    vim \
    tree \
    build-essential \
    python-dev \
    openssl \
    libssl-dev \
    libevent-dev \
    git \
    gnupg \
    dirmngr \
    apt-transport-https \
    wget \
    curl \
    ca-certificates \
    libffi-dev \
    && apt-get update && apt-get install -yf \
    && curl -k https://bootstrap.pypa.io/get-pip.py -o get-pip.py \
    && python get-pip.py \
    && rm -rf /var/lib/apt/lists/*


RUN adduser --disabled-password --gecos "" $VOLTTRON_USER

RUN mkdir /code && chown $VOLTTRON_USER.$VOLTTRON_USER /code \
  && echo "export PATH=/home/volttron/.local/bin:$PATH" > /home/volttron/.bashrc

############################################
# ENDING volttron_base image
############################################

FROM volttron_base AS volttron_core

# Note I couldn't get variable expansion on the chown argument to work here
# so must hard code the user.  Note this is a feature request for docker
# https://github.com/moby/moby/issues/35018
# COPY --chown=volttron:volttron . ${VOLTTRON_ROOT}

USER $VOLTTRON_USER

# The following lines ar no longer necesary because of the copy command above.
WORKDIR /code
RUN git clone https://github.com/VOLTTRON/volttron -b ${VOLTTRON_GIT_BRANCH}

WORKDIR /code/volttron
RUN echo "staring requirements install at `date`"
RUN pip install --user -r requirements.txt
RUN echo "requirements complete, installing package at `date`"
RUN pip install -e . --user
RUN echo "package installed at `date`"

############################################
# RABBITMQ SPECIFIC INSTALLATION
############################################
USER root
RUN ./scripts/rabbit_dependencies.sh $OS_TYPE $DIST

RUN mkdir /startup $VOLTTRON_HOME && \
    chown $VOLTTRON_USER.$VOLTTRON_USER $VOLTTRON_HOME
COPY ./core/entrypoint.sh /startup/entrypoint.sh
COPY ./core/bootstart.sh /startup/bootstart.sh
COPY ./core/setup-platform.py /startup/setup-platform.py
RUN chmod +x /startup/*

USER $VOLTTRON_USER
RUN mkdir $RMQ_ROOT
RUN set -eux \
    && wget -P $VOLTTRON_USER_HOME https://github.com/rabbitmq/rabbitmq-server/releases/download/v3.7.7/rabbitmq-server-generic-unix-3.7.7.tar.xz \
    && tar -xf $VOLTTRON_USER_HOME/rabbitmq-server-generic-unix-3.7.7.tar.xz --directory $RMQ_ROOT \
    && $RMQ_HOME/sbin/rabbitmq-plugins enable rabbitmq_management rabbitmq_federation rabbitmq_federation_management rabbitmq_shovel rabbitmq_shovel_management rabbitmq_auth_mechanism_ssl rabbitmq_trust_store
############################################


########################################
# The following lines should be run from any Dockerfile that
# is inheriting from this one as this will make the volttron
# run in the proper location.
#
# The user must be root at this point to allow gosu to work
########################################
USER root
WORKDIR ${VOLTTRON_USER_HOME}
ENTRYPOINT ["/startup/entrypoint.sh"]
CMD ["/startup/bootstart.sh"]


