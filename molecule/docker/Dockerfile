FROM quay.io/ansible/creator-ee:v0.20.0
# Cap the kubernetes python client below 32.0.0: 32.0.0 removed the deprecated
# kubernetes.client.apis.core_v1_api submodule, which kubernetes.core 4.0.0's
# k8s_exec module still imports, causing "NameError: name 'core_v1_api' is not
# defined" and breaking any molecule test that execs into a pod (e.g. metrics-test).
RUN pip install jmespath 'kubernetes<32'
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml -p /usr/share/ansible/collections \
 && rm /tmp/requirements.yml
RUN curl -L https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | VERIFY_CHECKSUM=false bash && helm version
