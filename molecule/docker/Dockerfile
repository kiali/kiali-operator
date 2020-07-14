FROM quay.io/ansible/molecule:3.0.6
RUN apk add gettext gcc libc-dev
RUN pip install openshift junit-xml jmespath docker kubernetes
RUN ansible-galaxy collection install community.kubernetes
