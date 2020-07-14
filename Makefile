# Needed for Travis - it won't like the version regex check otherwise
SHELL=/bin/bash

# Directories based on the root project directory
ROOTDIR=$(CURDIR)
OUTDIR=${ROOTDIR}/_output

# Identifies the current build.
VERSION ?= v1.21.0-SNAPSHOT
COMMIT_HASH ?= $(shell git rev-parse HEAD)

# Identifies the Kiali operator container image that will be built
OPERATOR_IMAGE_ORG ?= kiali
OPERATOR_CONTAINER_NAME ?= ${OPERATOR_IMAGE_ORG}/kiali-operator
OPERATOR_CONTAINER_VERSION ?= ${VERSION}
OPERATOR_QUAY_NAME ?= quay.io/${OPERATOR_CONTAINER_NAME}
OPERATOR_QUAY_TAG = ${OPERATOR_QUAY_NAME}:${OPERATOR_CONTAINER_VERSION}

# Determine if we should use Docker OR Podman - value must be one of "docker" or "podman"
DORP ?= docker

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
	@if [ "$(shell which helm 2>/dev/null 1>&2 && helm version --short | grep "v3" || echo -n "")" == "" ]; then \
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
	    mkdir -p "${OUTDIR}/helm-install" ;\
		cd "${OUTDIR}/helm-install" ;\
	    echo "curl -L \"https://get.helm.sh/helm-v3.2.4-$${os}-$${arch}.tar.gz\" > \"${OUTDIR}/helm-install/helm.tar.gz\"" ;\
	    curl -L "https://get.helm.sh/helm-v3.2.4-$${os}-$${arch}.tar.gz" > "${OUTDIR}/helm-install/helm.tar.gz" ;\
	    tar xzf "${OUTDIR}/helm-install/helm.tar.gz" ;\
	    mv "${OUTDIR}/helm-install/$${os}-$${arch}/helm" "${OUTDIR}/helm-install/helm" ;\
	    chmod +x "${OUTDIR}/helm-install/helm" ;\
	    rm -rf "${OUTDIR}/helm-install/$${os}-$${arch}" "${OUTDIR}/helm-install/helm.tar.gz" ;\
	  fi ;\
	fi

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

## build-helm-chart: Build Kiali operator helm chart
build-helm-chart: .download-helm-if-needed
	@echo Building helm chart for Kiali operator
	@mkdir -p "${OUTDIR}/charts"
	@cp -R "${ROOTDIR}/deploy/charts/kiali-operator" "${OUTDIR}/charts/"
	@rm -f "${OUTDIR}/charts/kiali-operator/values.yaml"
	@rm -f "${OUTDIR}/charts/kiali-operator/crds/kiali-crds.yaml"
	@OPERATOR_QUAY_NAME="${OPERATOR_QUAY_NAME}" OPERATOR_QUAY_TAG="${OPERATOR_CONTAINER_VERSION}" envsubst < "${ROOTDIR}/deploy/charts/kiali-operator/values.yaml" > "${OUTDIR}/charts/kiali-operator/values.yaml"
	@OPERATOR_QUAY_NAME="${OPERATOR_QUAY_NAME}" OPERATOR_QUAY_TAG="${OPERATOR_CONTAINER_VERSION}" envsubst < "${ROOTDIR}/deploy/charts/kiali-operator/crds/kiali-crds.yaml" > "${OUTDIR}/charts/kiali-operator/crds/kiali-crds.yaml"
	@OPERATOR_QUAY_NAME="${OPERATOR_QUAY_NAME}" OPERATOR_QUAY_TAG="${OPERATOR_CONTAINER_VERSION}" envsubst < "${ROOTDIR}/deploy/charts/kiali-operator/Chart.yaml" > "${OUTDIR}/charts/kiali-operator/Chart.yaml"
	@cat "${OUTDIR}/charts/kiali-operator/crds/kiali-crds.yaml" | grep -vE "^\s+labels:" | grep -vE  "^\s+app:"  | grep -vE  "^\s+version:" > temp-crds && mv temp-crds "${OUTDIR}/charts/kiali-operator/crds/kiali-crds.yaml"
	@helm package "${OUTDIR}/charts/kiali-operator" -d "${OUTDIR}" --app-version ${OPERATOR_CONTAINER_VERSION}
	@#rm -rf "${OUTDIR}/charts"

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
generate-all-in-one:
	@mkdir -p ${OUTDIR}
	@OPERATOR_IMAGE_VERSION=$${OPERATOR_IMAGE_VERSION:-${VERSION}} \
	  ${ROOTDIR}/deploy/merge-operator-yaml.sh --file ${OUTDIR}/kiali-operator-all-in-one.yaml
