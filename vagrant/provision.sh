#!/bin/bash

VM=$1
MODE=$2

if [ "$MODE" = 'aio' ]; then
    REGISTRY_PORT=4000
else
    REGISTRY_PORT=5000
fi
REGISTRY=operator.local:${REGISTRY_PORT}

function configure_commons {
    # Disable SELinux
    setenforce 0
    sed -i -r "s,^SELINUX=.+$,SELINUX=permissive," /etc/selinux/config

    yum -y install \
        epel-release \
        git \
        python-devel \
        vim-enhanced

    # Instal Development Tools
    yum -y groupinstall "Development Tools"

    # Install packages from EPEL
    yum -y install \
        python-pip

    yum clean all
}

function configure_docker {
    # Install Docker
    cat >/etc/yum.repos.d/docker.repo <<-EOF
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF
    yum -y install \
        docker-engine \
    && yum clean all
    pip install docker-py

    # Configure registry
    sed -i -r "s|(ExecStart)=(.+)|\1=/usr/bin/docker daemon --insecure-registry ${REGISTRY} --registry-mirror=http://${REGISTRY}|" /usr/lib/systemd/system/docker.service
    sed -i 's|^MountFlags=.*|MountFlags=shared|' /usr/lib/systemd/system/docker.service

    # Add user vagrant to group docker
    # This allows execution of docker commands without sudo
    usermod -aG docker vagrant

    # Start services
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker
}

function configure_operator {
    # Fetch and install pip packages
    pip install "ansible<2.0" tox
    sudo -u vagrant git clone https://github.com/openstack/kolla ~vagrant/kolla
    pip install ~vagrant/kolla
    pip install ~vagrant/kolla-mesos

    # Generate and copy configuration
    sudo -u vagrant bash -c "cd ~vagrant/kolla && tox -e genconfig"
    sudo -u vagrant bash -c "cd ~vagrant/kolla-mesos && tox -e genconfig"
    mkdir -p /etc/kolla-mesos
    cp -r ~vagrant/kolla/etc/kolla/ /etc/kolla
    cp ~vagrant/kolla-mesos/etc/kolla-mesos.conf.sample /etc/kolla-mesos/kolla-mesos.conf
    cp ~vagrant/kolla-mesos/etc/globals.yml /etc/kolla-mesos/globals.yml
    cp ~vagrant/kolla-mesos/etc/passwords.yml /etc/kolla-mesos/passwords.yml

    # Change network settings
    # TODO(nihilifer): Change kolla_internal_address when loadbalancing will be implemented.
    INTERNAL_INT=eth1
    EXTERNAL_INT=eth2
    HOST_IP=$(ip addr show $INTERNAL_INT | grep -Po 'inet \K[\d.]+')
    if [ "$MODE" = "multinode" ]; then
        sed -i -r "s,^[# ]*namespace.+$,namespace = ${REGISTRY}/kollaglue," /etc/kolla/kolla-build.conf
        sed -i -r "s,^[# ]*namespace.+$,namespace = ${REGISTRY}/kollaglue," /etc/kolla-mesos/kolla-mesos.conf
        sed -i -r "s,^[# ]*push.+$,push = True," /etc/kolla/kolla-build.conf
    fi
    for proj in kolla kolla-mesos ; do
        sed -i -r "s,^[# ]*kolla_internal_address:.+$,kolla_internal_address: \"$HOST_IP\"," /etc/$proj/globals.yml
        sed -i -r "s,^[# ]*network_interface:.+$,network_interface: \"$INTERNAL_INT\"," /etc/$proj/globals.yml
    done
    sed -i -r "s,^[# ]*public_interface:.+$,public_interface: \"$EXTERNAL_INT\"," /etc/kolla-mesos/kolla-mesos.conf
    sed -i -r "s,^[# ]*neutron_external_interface:.+$,neutron_external_interface: \"$EXTERNAL_INT\"," /etc/kolla/globals.yml
    sed -i -r "s,^[# ]*registry.+$,registry = operator.local:${REGISTRY_PORT}," /etc/kolla-mesos/globals.yml

    # Run Docker Registry
    if [[ ! $(docker ps -a -q -f name=registry) ]]; then
        docker run -d \
            --name=registry \
            --restart=always \
            -p ${REGISTRY_PORT}:5000 \
            -e STORAGE_PATH=/var/lib/registry \
            -v /data/host/registry-storage:/var/lib/registry \
            registry:2
    fi
}

configure_commons
configure_docker

if [ "$VM" = "operator" ]; then
    configure_operator
fi
