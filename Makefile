# Needed for Travis - it won't like the version regex check otherwise
SHELL=/bin/bash

# Directories based on the root project directory
ROOTDIR=$(CURDIR)
OUTDIR=${ROOTDIR}/_output

# list for multi-arch image publishing
TARGET_ARCHS ?= amd64 arm64 s390x ppc64le

# Identifies the current build.
VERSION ?= v1.53.0-SNAPSHOT
COMMIT_HASH ?= $(shell git rev-parse HEAD)

# Identifies the Kiali operator container image that will be built
OPERATOR_IMAGE_ORG ?= kiali
OPERATOR_CONTAINER_NAME ?= ${OPERATOR_IMAGE_ORG}/kiali-operator
OPERATOR_CONTAINER_VERSION ?= ${VERSION}
OPERATOR_QUAY_NAME ?= quay.io/${OPERATOR_CONTAINER_NAME}
OPERATOR_QUAY_TAG ?= ${OPERATOR_QUAY_NAME}:${OPERATOR_CONTAINER_VERSION}

# Determine if we should use Docker OR Podman - value must be one of "docker" or "podman"
DORP ?= docker

# The version of the SDK this Makefile will download if needed, and the corresponding base image
OPERATOR_SDK_VERSION ?= 1.13.1
OPERATOR_BASE_IMAGE_VERSION ?= v${OPERATOR_SDK_VERSION}
OPERATOR_BASE_IMAGE_REPO ?= quay.io/operator-framework/ansible-operator
# These are what we really want - but origin-ansible-operator does not support multiarch today.
# When that is fixed, we want to use this image instead of the image above.
# See: https://github.com/kiali/kiali/issues/4483
#OPERATOR_BASE_IMAGE_VERSION ?= 4.10
#OPERATOR_BASE_IMAGE_REPO ?= quay.io/openshift/origin-ansible-operator

.PHONY: help
help: Makefile
	@echo
	@echo "Targets"
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo

## clean: Cleans _output
clean:
	@rm -rf ${OUTDIR}

.download-operator-sdk-if-needed:
	@if [ "$(shell which operator-sdk 2>/dev/null || echo -n "")" == "" ]; then \
	  mkdir -p "${OUTDIR}/operator-sdk-install" ;\
	  if [ -x "${OUTDIR}/operator-sdk-install/operator-sdk" ]; then \
	    echo "You do not have operator-sdk installed in your PATH. Will use the one found here: ${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	  else \
	    echo "You do not have operator-sdk installed in your PATH. The binary will be downloaded to ${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	    curl -L https://github.com/operator-framework/operator-sdk/releases/download/v${OPERATOR_SDK_VERSION}/operator-sdk_linux_$$(test "$$(uname -m)" == "x86_64" && echo "amd64" || uname -m) > "${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	    chmod +x "${OUTDIR}/operator-sdk-install/operator-sdk" ;\
	  fi ;\
	fi

.ensure-operator-sdk-exists: .download-operator-sdk-if-needed
	@$(eval OP_SDK ?= $(shell which operator-sdk 2>/dev/null || echo "${OUTDIR}/operator-sdk-install/operator-sdk"))
	@"${OP_SDK}" version

## get-operator-sdk: Downloads the Operator SDK CLI if it is not already in PATH.
get-operator-sdk: .ensure-operator-sdk-exists
	@echo Operator SDK location: ${OP_SDK}

## build: Build Kiali operator container image.
.PHONY: build
build:
ifeq ($(DORP),docker)
	@echo Building container image for Kiali operator using docker
	docker build --pull -t ${OPERATOR_QUAY_TAG} --build-arg OPERATOR_BASE_IMAGE_REPO=${OPERATOR_BASE_IMAGE_REPO} --build-arg OPERATOR_BASE_IMAGE_VERSION=${OPERATOR_BASE_IMAGE_VERSION} -f ${ROOTDIR}/build/Dockerfile ${ROOTDIR}
else
	@echo Building container image for Kiali operator using podman
	podman build --pull -t ${OPERATOR_QUAY_TAG} --build-arg OPERATOR_BASE_IMAGE_REPO=${OPERATOR_BASE_IMAGE_REPO} --build-arg OPERATOR_BASE_IMAGE_VERSION=${OPERATOR_BASE_IMAGE_VERSION} -f ${ROOTDIR}/build/Dockerfile ${ROOTDIR}
endif

## push: Pushes the operator image to quay.
push:
ifeq ($(DORP),docker)
	@echo Pushing Kiali operator image using docker
	docker push ${OPERATOR_QUAY_TAG}
else
	@echo Pushing Kiali operator image using podman
	podman push ${OPERATOR_QUAY_TAG}
endif

## validate: Checks the latest version of the OLM bundle metadata for correctness.
validate: .ensure-operator-sdk-exists
	@printf "==========\nValidating kiali-ossm metadata\n==========\n"
	@mkdir -p ${OUTDIR}/kiali-ossm && rm -rf ${OUTDIR}/kiali-ossm/* && cp -R ./manifests/kiali-ossm ${OUTDIR} && cat ./manifests/kiali-ossm/manifests/kiali.clusterserviceversion.yaml | KIALI_OPERATOR_VERSION="2.0.0" KIALI_OLD_OPERATOR_VERSION="1.0.0" KIALI_OPERATOR_TAG=":2.0.0" KIALI_1_24_TAG=":1.24.0" KIALI_1_12_TAG=":1.12.0" KIALI_1_0_TAG=":1.0.0" CREATED_AT="2021-01-01T00:00:00Z" envsubst > ${OUTDIR}/kiali-ossm/manifests/kiali.clusterserviceversion.yaml && ${OP_SDK} bundle validate --verbose ${OUTDIR}/kiali-ossm
	@printf "==========\nValidating the latest version of kiali-community metadata\n==========\n"
	@for d in $$(ls -1d manifests/kiali-community/* | sort -V | grep -v ci.yaml | tail -n 1); do ${OP_SDK} bundle --verbose validate $$d; done
	@printf "==========\nValidating the latest version of kiali-upstream metadata\n==========\n"
	@for d in $$(ls -1d manifests/kiali-upstream/* | sort -V | grep -v ci.yaml | tail -n 1); do ${OP_SDK} bundle --verbose validate $$d; done

## validate-cr: Ensures the example CR is valid according to the CRD schema
validate-cr:
	${ROOTDIR}/crd-docs/bin/validate-kiali-cr.sh --kiali-cr-file ${ROOTDIR}/crd-docs/cr/kiali.io_v1alpha1_kiali.yaml

## gen-crd-doc: Generates documentation for the Kiali CR configuration
gen-crd-doc:
	mkdir -p ${OUTDIR}/crd-docs
	${DORP} run -v ${OUTDIR}/crd-docs:/opt/crd-docs-generator/output -v ${ROOTDIR}/crd-docs/config:/opt/crd-docs-generator/config quay.io/giantswarm/crd-docs-generator:0.9.0 --config /opt/crd-docs-generator/config/apigen-config.yaml

# Ensure "docker buildx" is available and enabled. For more details, see: https://github.com/docker/buildx/blob/master/README.md
# This does a few things:
#  1. Makes sure docker is in PATH
#  2. Downloads and installs buildx if no version of buildx is installed yet
#  3. Makes sure any installed buildx is a required version or newer
#  4. Makes sure the user has enabled buildx (either by default or by setting DOCKER_CLI_EXPERIMENTAL env var to 'enabled')
#  Thus, this target will only ever succeed if a required (or newer) version of 'docker buildx' is available and enabled.
.ensure-docker-buildx:
	@if ! which docker > /dev/null 2>&1; then echo "'docker' is not in your PATH."; exit 1; fi
	@required_buildx_version="0.4.2"; \
	if ! DOCKER_CLI_EXPERIMENTAL="enabled" docker buildx version > /dev/null 2>&1 ; then \
	  buildx_download_url="https://github.com/docker/buildx/releases/download/v$${required_buildx_version}/buildx-v$${required_buildx_version}.${GOOS}-${GOARCH}"; \
	  echo "You do not have 'docker buildx' installed. Will now download from [$${buildx_download_url}] and install it to [${HOME}/.docker/cli-plugins]."; \
	  mkdir -p ${HOME}/.docker/cli-plugins; \
	  curl -L --output ${HOME}/.docker/cli-plugins/docker-buildx "$${buildx_download_url}"; \
	  chmod a+x ${HOME}/.docker/cli-plugins/docker-buildx; \
	  installed_version="$$(DOCKER_CLI_EXPERIMENTAL="enabled" docker buildx version || echo "unknown")"; \
	  if docker buildx version > /dev/null 2>&1; then \
	    echo "'docker buildx' has been installed and is enabled [version=$${installed_version}]"; \
	  else \
	    echo "An attempt to install 'docker buildx' has been made but it either failed or is not enabled by default. [version=$${installed_version}]"; \
	    echo "Set DOCKER_CLI_EXPERIMENTAL=enabled to enable it."; \
	    exit 1; \
	  fi \
	fi; \
	current_buildx_version="$$(DOCKER_CLI_EXPERIMENTAL=enabled docker buildx version 2>/dev/null | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/g')"; \
	is_valid_buildx_version="$$(if [ "$$(printf $${required_buildx_version}\\n$${current_buildx_version} | sort -V | head -n1)" == "$${required_buildx_version}" ]; then echo "true"; else echo "false"; fi)"; \
	if [ "$${is_valid_buildx_version}" == "true" ]; then \
	  echo "A valid version of 'docker buildx' is available: $${current_buildx_version}"; \
	else \
	  echo "You have an older version of 'docker buildx' that is not compatible. Please upgrade to at least v$${required_buildx_version}"; \
	  exit 1; \
	fi; \
	if docker buildx version > /dev/null 2>&1; then \
	  echo "'docker buildx' is enabled"; \
	else \
	  echo "'docker buildx' is not enabled. Set DOCKER_CLI_EXPERIMENTAL=enabled if you want to use it."; \
	  exit 1; \
	fi

# Ensure a local builder for multi-arch build. For more details, see: https://github.com/docker/buildx/blob/master/README.md#building-multi-platform-images
.ensure-buildx-builder: .ensure-docker-buildx
	@if ! docker buildx inspect kiali-builder > /dev/null 2>&1; then \
	  echo "The buildx builder instance named 'kiali-builder' does not exist. Creating one now."; \
	  if ! docker buildx create --name=kiali-builder --driver-opt=image=moby/buildkit:v0.8.0; then \
	    echo "Failed to create the buildx builder 'kiali-builder'"; \
	    exit 1; \
	  fi \
	fi; \
	if [[ $$(uname -s) == "Linux" ]]; then \
	  echo "Ensuring QEMU is set up for this Linux host"; \
	  if ! docker run --privileged --rm quay.io/kiali/binfmt:latest --install all; then \
	    echo "Failed to ensure QEMU is set up. This build will be allowed to continue, but it may fail at a later step."; \
	  fi \
	fi

## container-multi-arch-push-kiali-operator-quay: Pushes the Kiali Operator multi-arch image to quay.
container-multi-arch-push-kiali-operator-quay: .ensure-buildx-builder
	@echo Pushing Kiali Operator multi-arch image to ${OPERATOR_QUAY_TAG} using docker buildx
	docker buildx build --build-arg OPERATOR_BASE_IMAGE_REPO=${OPERATOR_BASE_IMAGE_REPO} --build-arg OPERATOR_BASE_IMAGE_VERSION=${OPERATOR_BASE_IMAGE_VERSION} --push --pull --no-cache --builder=kiali-builder $(foreach arch,${TARGET_ARCHS},--platform=linux/${arch}) $(foreach tag,${OPERATOR_QUAY_TAG},--tag=${tag}) -f ${ROOTDIR}/build/Dockerfile ${ROOTDIR}
