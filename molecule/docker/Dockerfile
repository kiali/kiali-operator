FROM quay.io/ansible/molecule:3.0.6
RUN apk add gettext gcc libc-dev
RUN pip install openshift junit-xml jmespath docker 'kubernetes==11.0.0'
RUN ansible-galaxy collection install community.kubernetes
RUN apk add curl bash openssl
RUN curl -L https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash && helm version
