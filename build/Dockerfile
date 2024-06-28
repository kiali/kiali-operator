ARG OPERATOR_BASE_IMAGE_VERSION
ARG OPERATOR_BASE_IMAGE_REPO
FROM ${OPERATOR_BASE_IMAGE_REPO}:${OPERATOR_BASE_IMAGE_VERSION}

USER root
# see https://github.com/operator-framework/operator-sdk/issues/5745
RUN yum remove -y subscription-manager python3-subscription-manager-rhsm
RUN yum update -y && yum clean all
USER ${USER_UID}

COPY roles/ ${HOME}/roles/
COPY playbooks/ ${HOME}/playbooks/
COPY watches-k8s.yaml ${HOME}/watches-k8s.yaml
COPY watches-os.yaml ${HOME}/watches-os.yaml
COPY watches-k8s-ns.yaml ${HOME}/watches-k8s-ns.yaml
COPY watches-os-ns.yaml ${HOME}/watches-os-ns.yaml

# pull in jmespath py library for json processing
RUN python3 -m pip install jmespath

COPY requirements.yml ${HOME}/requirements.yml
RUN ansible-galaxy collection install -r ${HOME}/requirements.yml \
 && chmod -R ug+rwx ${HOME}/.ansible

RUN cp /etc/ansible/ansible.cfg ${HOME}/ansible-profiler.cfg && echo "callbacks_enabled = profile_tasks" >> ${HOME}/ansible-profiler.cfg && echo "callback_whitelist = profile_tasks" >> ${HOME}/ansible-profiler.cfg
