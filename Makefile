# Needed for Travis - it won't like the version regex check otherwise
SHELL=/bin/bash

# Directories based on the root project directory
ROOTDIR=$(CURDIR)
OUTDIR=${ROOTDIR}/_output

# Identifies the current build.
VERSION ?= v1.22.0-SNAPSHOT
COMMIT_HASH ?= $(shell git rev-parse HEAD)

# Identifies the Kiali operator container image that will be built
OPERATOR_IMAGE_ORG ?= kiali
OPERATOR_CONTAINER_NAME ?= ${OPERATOR_IMAGE_ORG}/kiali-operator
OPERATOR_CONTAINER_VERSION ?= ${VERSION}
OPERATOR_QUAY_NAME ?= quay.io/${OPERATOR_CONTAINER_NAME}
OPERATOR_QUAY_TAG = ${OPERATOR_QUAY_NAME}:${OPERATOR_CONTAINER_VERSION}

# Determine if we should use Docker OR Podman - value must be one of "docker" or "podman"
DORP ?= docker

# When building the helm chart, this is the helm version to use
HELM_VERSION ?= v3.2.4

.PHONY: help
help: Makefile
	@echo
	@echo "Targets"
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo

## clean: Cleans _output
clean:
	@rm -rf ${OUTDIR}

.download-helm-if-needed:
	@$(eval HELM ?= $(shell if (which helm 2>/dev/null 1>&2 && helm version --short 2>/dev/null | grep -q "v3"); then echo "helm"; else echo "${OUTDIR}/helm-install/helm"; fi))
	@if ! which ${HELM} 2>/dev/null 1>&2; then \
	  mkdir -p "${OUTDIR}/helm-install" ;\
	  if [ -x "${OUTDIR}/helm-install/helm" ]; then \
	    echo "You do not have helm installed in your PATH. Will use the one found here: ${OUTDIR}/helm-install/helm" ;\
	  else \
	    echo "You do not have helm installed in your PATH. The binary will be downloaded to ${OUTDIR}/helm-install/helm" ;\
	    os=$$(uname -s | tr '[:upper:]' '[:lower:]') ;\
	    arch="" ;\
	    case $$(uname -m) in \
	        i386)   arch="386" ;; \
	        i686)   arch="386" ;; \
	        x86_64) arch="amd64" ;; \
	        arm)    dpkg --print-architecture | grep -q "arm64" && arch="arm64" || arch="arm" ;; \
	    esac ;\
	    cd "${OUTDIR}/helm-install" ;\
	    curl -L "https://get.helm.sh/helm-${HELM_VERSION}-$${os}-$${arch}.tar.gz" > "${OUTDIR}/helm-install/helm.tar.gz" ;\
	    tar xzf "${OUTDIR}/helm-install/helm.tar.gz" ;\
	    mv "${OUTDIR}/helm-install/$${os}-$${arch}/helm" "${OUTDIR}/helm-install/helm" ;\
	    chmod +x "${OUTDIR}/helm-install/helm" ;\
	    rm -rf "${OUTDIR}/helm-install/$${os}-$${arch}" "${OUTDIR}/helm-install/helm.tar.gz" ;\
	  fi ;\
	fi
	@echo Will use this helm executable: ${HELM}

.download-operator-sdk-if-needed:
	@if [ "$(shell which operator-sdk 2>/dev/null || echo -n "")" == "" ]; then \
	  mkdir -p "${OUTDIR}/operator-sdk-install" ;\
	  if [ -x "${OUTDIR}/operator-sdk-install/operator-sdk" ]; then \
	    echo "You do not have operator-sdk installed in your PATH. Will use the one found here: ${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	  else \
	    echo "You do not have operator-sdk installed in your PATH. The binary will be downloaded to ${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	    curl -L https://github.com/operator-framework/operator-sdk/releases/download/v0.17.0/operator-sdk-v0.17.0-$$(uname -m)-linux-gnu > "${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	    chmod +x "${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	  fi ;\
	fi

.ensure-operator-sdk-exists: .download-operator-sdk-if-needed
	@$(eval OP_SDK ?= $(shell which operator-sdk 2>/dev/null || echo "${OUTDIR}/operator-sdk-install/operator-sdk"))
	@"${OP_SDK}" version

## build: Build Kiali operator container image.
build: .ensure-operator-sdk-exists
	@echo Building container image for Kiali operator using operator-sdk
	cd "${ROOTDIR}" && "${OP_SDK}" build --image-builder ${DORP} --image-build-args "--pull" "${OPERATOR_QUAY_TAG}"

## build-helm-chart: Build Kiali operator Helm Chart
build-helm-chart: .download-helm-if-needed
	@echo Building Helm Chart for Kiali operator
	@rm -rf "${OUTDIR}/charts"
	@mkdir -p "${OUTDIR}/charts"
	@cp -R "${ROOTDIR}/deploy/charts/kiali-operator" "${OUTDIR}/charts/"
	@HELM_IMAGE_REPO="${OPERATOR_QUAY_NAME}" HELM_IMAGE_TAG="${OPERATOR_CONTAINER_VERSION}" envsubst < "${ROOTDIR}/deploy/charts/kiali-operator/values.yaml" > "${OUTDIR}/charts/kiali-operator/values.yaml"
	@"${HELM}" lint "${OUTDIR}/charts/kiali-operator"
	@"${HELM}" package "${OUTDIR}/charts/kiali-operator" -d "${OUTDIR}/charts" --version ${OPERATOR_CONTAINER_VERSION} --app-version ${OPERATOR_CONTAINER_VERSION}

## update-helm-repo: Build the latest Kiali operator Helm Chart and adds it to the local Helm repo directory.
update-helm-repo: build-helm-chart
	cp "${OUTDIR}/charts/kiali-operator-${OPERATOR_CONTAINER_VERSION}.tgz" "${ROOTDIR}/docs/charts"
	"${HELM}" repo index "${ROOTDIR}/docs/charts" --url https://kiali.org/kiali-operator/charts

## push: Pushes the operator image to quay.
push:
ifeq ($(DORP),docker)
	@echo Pushing Kiali operator image using docker
	docker push ${OPERATOR_QUAY_TAG}
else
	@echo Pushing Kiali operator image using podman
	podman push ${OPERATOR_QUAY_TAG}
endif

## generate-all-in-one: Creates the all-in-one yaml file that can be used to deploy the operator via kubectl apply.
generate-all-in-one: build-helm-chart
	@mkdir -p ${OUTDIR}
	@OPERATOR_IMAGE_VERSION=$${OPERATOR_IMAGE_VERSION:-${VERSION}} \
	  ${ROOTDIR}/deploy/merge-operator-yaml.sh --file ${OUTDIR}/kiali-operator-all-in-one.yaml
