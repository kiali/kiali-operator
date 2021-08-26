FROM quay.io/kiali/ansible-molecule:3.1.5
RUN apk add gettext gcc libc-dev
RUN pip install openshift junit-xml jmespath docker kubernetes
RUN ansible-galaxy collection install kubernetes.core
RUN apk add curl bash openssl
RUN curl -L https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash && helm version
