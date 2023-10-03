FROM quay.io/ansible/creator-ee:v0.20.0
RUN pip install jmespath kubernetes
RUN ansible-galaxy collection install -p /usr/share/ansible/collections community.general kubernetes.core
RUN curl -L https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | VERIFY_CHECKSUM=false bash && helm version
