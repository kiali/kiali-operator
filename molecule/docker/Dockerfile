FROM quay.io/ansible/creator-ee:v0.20.0
RUN pip install jmespath kubernetes
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml -p /usr/share/ansible/collections \
 && rm /tmp/requirements.yml
RUN curl -L https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | VERIFY_CHECKSUM=false bash && helm version
