FROM quay.io/ansible/molecule:3.0.4
RUN apk add gettext gcc libc-dev
RUN pip install openshift junit-xml jmespath docker kubernetes
RUN ansible-galaxy collection install community.kubernetes

# fixes https://github.com/ansible-community/molecule/pull/2690 - take this out when we move to 3.0.5
RUN mkdir -p /usr/share/ansible && ln -s /root/.ansible/collections /usr/share/ansible/collections
