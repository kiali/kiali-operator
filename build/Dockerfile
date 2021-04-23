ARG OPERATOR_BASE_IMAGE_VERSION
FROM quay.io/openshift/origin-ansible-operator:${OPERATOR_BASE_IMAGE_VERSION}

COPY roles/ ${HOME}/roles/
COPY playbooks/ ${HOME}/playbooks/
COPY watches.yaml ${HOME}/watches.yaml

COPY requirements.yml ${HOME}/requirements.yml
RUN ansible-galaxy collection install -r ${HOME}/requirements.yml \
 && chmod -R ug+rwx ${HOME}/.ansible

RUN cp /etc/ansible/ansible.cfg ${HOME}/ansible-profiler.cfg && echo "callback_whitelist = profile_tasks" >> ${HOME}/ansible-profiler.cfg
