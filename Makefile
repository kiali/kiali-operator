# Needed for Travis - it won't like the version regex check otherwise
SHELL=/bin/bash

# Directories based on the root project directory
ROOTDIR=$(CURDIR)
OUTDIR=${ROOTDIR}/_output

# list for multi-arch image publishing
TARGET_ARCHS ?= amd64 arm64 s390x ppc64le

# Identifies the current build.
VERSION ?= v2.18.0-SNAPSHOT
COMMIT_HASH ?= $(shell git rev-parse HEAD)

# Identifies the Kiali operator container image that will be built
OPERATOR_IMAGE_ORG ?= kiali
OPERATOR_CONTAINER_NAME ?= ${OPERATOR_IMAGE_ORG}/kiali-operator
OPERATOR_CONTAINER_VERSION ?= ${VERSION}
OPERATOR_QUAY_NAME ?= quay.io/${OPERATOR_CONTAINER_NAME}
OPERATOR_QUAY_TAG ?= ${OPERATOR_QUAY_NAME}:${OPERATOR_CONTAINER_VERSION}

# Determine if we should use Docker OR Podman - value must be one of "docker" or "podman"
DORP ?= docker

# The version of OPM this Makefile will download if needed, and the corresponding base image
# Note: operator-sdk and opm are both part of operator-framework and released together
# Auto-discover OPM version using GitHub API to ensure compatibility with operator-framework releases
# You can override this by setting OPM_VERSION explicitly: make validate OPM_VERSION=v1.50.0
OPM_VERSION ?= $(shell result=$$(curl -s --max-time 5 https://api.github.com/repos/operator-framework/operator-registry/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null); if [ -n "$$result" ]; then echo "$$result"; else echo "v1.56.0"; fi)
OPERATOR_BASE_IMAGE_VERSION ?= v1.37.2
OPERATOR_BASE_IMAGE_REPO ?= quay.io/operator-framework/ansible-operator

.PHONY: help
help: Makefile
	@echo
	@echo "Targets"
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo

## clean: Cleans _output
clean:
	@rm -rf ${OUTDIR}

.download-opm-if-needed:
	@if [ "$(shell which opm 2>/dev/null || echo -n "")" == "" ]; then \
	  mkdir -p "${OUTDIR}/opm-install" ;\
	  if [ -x "${OUTDIR}/opm-install/opm" ]; then \
	    echo "You do not have opm installed in your PATH. Will use the one found here: ${OUTDIR}/opm-install/opm" ;\
	  else \
	    echo "You do not have opm installed in your PATH. The binary will be downloaded to ${OUTDIR}/opm-install/opm" ;\
	    curl -L https://github.com/operator-framework/operator-registry/releases/download/${OPM_VERSION}/linux-$$(test "$$(uname -m)" == "x86_64" && echo "amd64" || uname -m)-opm > "${OUTDIR}/opm-install/opm" ;\
	    chmod +x "${OUTDIR}/opm-install/opm" ;\
	  fi ;\
	fi

.ensure-opm-exists: .download-opm-if-needed
	@$(eval OPM ?= $(shell which opm 2>/dev/null || echo "${OUTDIR}/opm-install/opm"))
	@"${OPM}" version

## get-opm: Downloads the OPM CLI if it is not already in PATH.
get-opm: .ensure-opm-exists
	@echo OPM location: ${OPM}

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
validate: .ensure-opm-exists validate-crd-sync verify-kiali-server-permissions verify-defaults
	@printf "========== Validating kiali-ossm metadata ==========\n"
	@mkdir -p ${OUTDIR}/kiali-ossm-validation/bundle && rm -rf ${OUTDIR}/kiali-ossm-validation/* && mkdir -p ${OUTDIR}/kiali-ossm-validation/bundle && cp -R ./manifests/kiali-ossm/manifests ${OUTDIR}/kiali-ossm-validation/bundle/ && cp -R ./manifests/kiali-ossm/metadata ${OUTDIR}/kiali-ossm-validation/bundle/ && cat ./manifests/kiali-ossm/manifests/kiali.clusterserviceversion.yaml | KIALI_OPERATOR="registry.redhat.io/openshift-service-mesh/kiali-rhel9-operator:2.4.5" KIALI_OPERATOR_VERSION="2.4.5" CREATED_AT="2021-01-01T00:00:00Z" envsubst > ${OUTDIR}/kiali-ossm-validation/bundle/manifests/kiali.clusterserviceversion.yaml; \
	if ${OPM} render ${OUTDIR}/kiali-ossm-validation/bundle --output yaml > ${OUTDIR}/kiali-ossm-validation/catalog.yaml 2>/dev/null; then \
		printf "✓ kiali-ossm bundle structure is valid and can be rendered\n"; \
	else \
		printf "✗ kiali-ossmundle rendering failed - check manifest syntax\n"; \
		exit 1; \
	fi
	@printf "========== Validating the latest version of kiali-upstream metadata ==========\n"
	@for d in $$(find . -type d -name "[0-9]*" | grep -E "/[0-9]+\.[0-9]+\.[0-9]+$$" | sort -V | tail -n 1); do \
		mkdir -p ${OUTDIR}/validation/bundle && rm -rf ${OUTDIR}/validation/* && mkdir -p ${OUTDIR}/validation/bundle && cp -R $$d/manifests ${OUTDIR}/validation/bundle/ && cp -R $$d/metadata ${OUTDIR}/validation/bundle/; \
		if ${OPM} render ${OUTDIR}/validation/bundle --output yaml > ${OUTDIR}/validation/catalog.yaml 2>/dev/null; then \
			printf "✓ [$$d] bundle structure is valid and can be rendered\n"; \
		else \
			printf "✗ [$$d] bundle rendering failed - check manifest syntax\n"; \
			exit 1; \
		fi; \
	done

## validate-cr: Ensures the example CR is valid according to the CRD schema
validate-cr:
	@printf "\n========== Validating the Kiali CR ==========\n"
	${ROOTDIR}/crd-docs/bin/validate-kiali-cr.sh --kiali-cr-file ${ROOTDIR}/crd-docs/cr/kiali.io_v1alpha1_kiali.yaml
	@printf "\n========== Validating the OSSMConsole CR ==========\n"
	${ROOTDIR}/crd-docs/bin/validate-ossmconsole-cr.sh --cr-file ${ROOTDIR}/crd-docs/cr/kiali.io_v1alpha1_ossmconsole.yaml

## verify-kiali-server-permissions: Verifies that Kiali Server permissions are correctly mirrored in operator roles
verify-kiali-server-permissions:
	@printf "\n========== Verifying Kiali Server Permissions ==========\n"
	${ROOTDIR}/hack/verify-kiali-server-permissions.sh

## verify-defaults: Verifies that CRD defaults match the corresponding Ansible defaults
verify-defaults:
	@printf "\n========== Verifying CRD Defaults ==========\n"
	${ROOTDIR}/hack/verify-crd-defaults.sh

.gen-crd-doc-kiali:
	mkdir -p ${OUTDIR}/crd-docs
	${DORP} run -v ${OUTDIR}/crd-docs:/opt/crd-docs-generator/output:z -v ${ROOTDIR}/crd-docs/config/kiali:/opt/crd-docs-generator/config:z quay.io/giantswarm/crd-docs-generator:0.9.0 --config /opt/crd-docs-generator/config/apigen-config.yaml

.gen-crd-doc-ossmconsole:
	mkdir -p ${OUTDIR}/crd-docs
	${DORP} run -v ${OUTDIR}/crd-docs:/opt/crd-docs-generator/output:z -v ${ROOTDIR}/crd-docs/config/ossmconsole:/opt/crd-docs-generator/config:z quay.io/giantswarm/crd-docs-generator:0.9.0 --config /opt/crd-docs-generator/config/apigen-config.yaml

## gen-crd-doc: Generates documentation for the Kiali CR and OSSMConsole CR configuration
gen-crd-doc: .gen-crd-doc-kiali .gen-crd-doc-ossmconsole

## sync-crds: Synchronizes all CRD files from the golden copies
sync-crds:
	@echo "Synchronizing Kiali CRD from golden copy: crd-docs/crd/kiali.io_kialis.yaml"

	@if [ -d "../helm-charts/kiali-operator/crds" ]; then \
		echo "  -> helm-charts/kiali-operator/crds/crds.yaml - with YAML document separators"; \
		echo "---" > ../helm-charts/kiali-operator/crds/crds.yaml; \
		cat crd-docs/crd/kiali.io_kialis.yaml >> ../helm-charts/kiali-operator/crds/crds.yaml; \
		echo "..." >> ../helm-charts/kiali-operator/crds/crds.yaml; \
	else \
		echo "  -> helm-charts/kiali-operator/crds/crds.yaml - SKIPPED - directory not found"; \
	fi

	@echo "  -> manifests/kiali-ossm/manifests/kiali.crd.yaml - direct copy"
	@cp crd-docs/crd/kiali.io_kialis.yaml manifests/kiali-ossm/manifests/kiali.crd.yaml

	@latest_version=$$(ls -1 manifests/kiali-upstream/ | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$$" | sort -V | tail -n 1); \
	if [ -n "$$latest_version" ]; then \
		echo "  -> manifests/kiali-upstream/$$latest_version/manifests/kiali.crd.yaml - direct copy"; \
		cp crd-docs/crd/kiali.io_kialis.yaml manifests/kiali-upstream/$$latest_version/manifests/kiali.crd.yaml; \
	else \
		echo "ERROR: No version directories found under manifests/kiali-upstream/"; \
		exit 1; \
	fi

	@echo "Synchronizing OSSMConsole CRD from golden copy: crd-docs/crd/kiali.io_ossmconsoles.yaml"

	@echo "  -> manifests/kiali-ossm/manifests/ossmconsole.crd.yaml - direct copy"
	@cp crd-docs/crd/kiali.io_ossmconsoles.yaml manifests/kiali-ossm/manifests/ossmconsole.crd.yaml

	@if [ -d "../helm-charts/kiali-operator/templates" ]; then \
		echo "  -> helm-charts/kiali-operator/templates/ossmconsole-crd.yaml - updating CRD content while preserving template structure"; \
		template_file="../helm-charts/kiali-operator/templates/ossmconsole-crd.yaml"; \
		temp_file=$$(mktemp); \
		trap "rm -f $$temp_file" EXIT; \
		start_line=$$(grep -n "^---$$" "$$template_file" | head -1 | cut -d: -f1); \
		if [ -z "$$start_line" ]; then \
			echo "ERROR: Could not find YAML document start marker --- in $$template_file"; \
			exit 1; \
		fi; \
		head -n "$$start_line" "$$template_file" > "$$temp_file"; \
		cat crd-docs/crd/kiali.io_ossmconsoles.yaml >> "$$temp_file"; \
		end_line=$$(grep -n "^\\.\\.\\.$$" "$$template_file" | tail -1 | cut -d: -f1); \
		if [ -n "$$end_line" ]; then \
			tail -n +"$$end_line" "$$template_file" >> "$$temp_file"; \
		else \
			after_crd_line=$$(grep -n "^{{-" "$$template_file" | tail -1 | cut -d: -f1); \
			if [ -n "$$after_crd_line" ]; then \
				tail -n +"$$after_crd_line" "$$template_file" >> "$$temp_file"; \
			fi; \
		fi; \
		mv "$$temp_file" "$$template_file"; \
	else \
		echo "  -> helm-charts/kiali-operator/templates/ossmconsole-crd.yaml - SKIPPED - directory not found"; \
	fi

	@echo "CRD synchronization complete."

## validate-crd-sync: Validates that all CRD files are in sync with the golden copies
validate-crd-sync:
	@echo "Validating CRD synchronization..."
	@temp_dir=$$(mktemp -d) && \
	trap "rm -rf $$temp_dir" EXIT && \
	latest_version=$$(ls -1 manifests/kiali-upstream/ | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$$" | sort -V | tail -n 1) && \
	if [ -z "$$latest_version" ]; then \
		echo "ERROR: No version directories found under manifests/kiali-upstream/"; \
		exit 1; \
	fi && \
	if [ -d "../helm-charts/kiali-operator/crds" ]; then \
		echo "Validating helm-charts Kiali CRD synchronization..."; \
		echo "---" > "$$temp_dir/expected-helm-kiali.yaml"; \
		cat crd-docs/crd/kiali.io_kialis.yaml >> "$$temp_dir/expected-helm-kiali.yaml"; \
		echo "..." >> "$$temp_dir/expected-helm-kiali.yaml"; \
		if ! diff -q "$$temp_dir/expected-helm-kiali.yaml" ../helm-charts/kiali-operator/crds/crds.yaml >/dev/null 2>&1; then \
			echo "ERROR: Helm Kiali CRD is out of sync! Run 'make sync-crds' to fix."; \
			exit 1; \
		fi; \
		echo "✓ Helm-charts Kiali CRD is in sync"; \
		if [ -f "../helm-charts/kiali-operator/templates/ossmconsole-crd.yaml" ]; then \
			echo "Validating helm-charts OSSMConsole CRD template..."; \
			template_file="../helm-charts/kiali-operator/templates/ossmconsole-crd.yaml"; \
			start_line=$$(grep -n "^---$$" "$$template_file" | head -1 | cut -d: -f1); \
			if [ -z "$$start_line" ]; then \
				echo "ERROR: Could not find YAML document start marker --- in $$template_file"; \
				exit 1; \
			fi; \
			end_line=$$(grep -n "^\\.\\.\\.$$" "$$template_file" | tail -1 | cut -d: -f1); \
			if [ -n "$$end_line" ]; then \
				end_content_line=$$((end_line - 1)); \
			else \
				after_crd_line=$$(grep -n "^{{-" "$$template_file" | tail -1 | cut -d: -f1); \
				if [ -n "$$after_crd_line" ]; then \
					end_content_line=$$((after_crd_line - 1)); \
				else \
					end_content_line=$$(wc -l < "$$template_file"); \
				fi; \
			fi; \
			start_content_line=$$((start_line + 1)); \
			sed -n "$${start_content_line},$${end_content_line}p" "$$template_file" > "$$temp_dir/template-crd-content.yaml"; \
			if ! diff -q crd-docs/crd/kiali.io_ossmconsoles.yaml "$$temp_dir/template-crd-content.yaml" >/dev/null 2>&1; then \
				echo "ERROR: Helm OSSMConsole CRD template content is out of sync! Run 'make sync-crds' to fix."; \
				exit 1; \
			fi; \
			echo "✓ Helm-charts OSSMConsole CRD template is in sync"; \
		else \
			echo "WARNING: OSSMConsole CRD template not found in helm-charts"; \
		fi; \
	else \
		echo "WARNING: Skipping helm-charts CRD validation - ../helm-charts directory not found"; \
		echo "  This is normal during CI builds where helm-charts repo is not checked out"; \
	fi && \
	if ! diff -q crd-docs/crd/kiali.io_kialis.yaml manifests/kiali-ossm/manifests/kiali.crd.yaml >/dev/null 2>&1; then \
		echo "ERROR: OSSM Kiali CRD is out of sync! Run 'make sync-crds' to fix."; \
		exit 1; \
	fi && \
	if ! diff -q crd-docs/crd/kiali.io_kialis.yaml manifests/kiali-upstream/$$latest_version/manifests/kiali.crd.yaml >/dev/null 2>&1; then \
		echo "ERROR: Upstream Kiali CRD [$$latest_version] is out of sync! Run 'make sync-crds' to fix."; \
		exit 1; \
	fi && \
	if ! diff -q crd-docs/crd/kiali.io_ossmconsoles.yaml manifests/kiali-ossm/manifests/ossmconsole.crd.yaml >/dev/null 2>&1; then \
		echo "ERROR: OSSM OSSMConsole CRD is out of sync! Run 'make sync-crds' to fix."; \
		exit 1; \
	fi && \
	echo "✓ All CRD files are in sync with the golden copies"



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
	  if ! docker buildx create --name=kiali-builder --driver-opt=image=moby/buildkit:v0.13.2; then \
	    echo "Failed to create the buildx builder 'kiali-builder'"; \
	    exit 1; \
	  fi \
	fi; \
	if [[ $$(uname -s) == "Linux" ]]; then \
	  echo "Ensuring QEMU is set up for this Linux host"; \
	  if ! docker run --privileged --rm tonistiigi/binfmt:latest --install all; then \
	    echo "Failed to ensure QEMU is set up. This build will be allowed to continue, but it may fail at a later step."; \
	  fi \
	fi

## container-multi-arch-push-kiali-operator-quay: Pushes the Kiali Operator multi-arch image to quay.
container-multi-arch-push-kiali-operator-quay: .ensure-buildx-builder
	@echo Pushing Kiali Operator multi-arch image to ${OPERATOR_QUAY_TAG} using docker buildx
	docker buildx build --build-arg OPERATOR_BASE_IMAGE_REPO=${OPERATOR_BASE_IMAGE_REPO} --build-arg OPERATOR_BASE_IMAGE_VERSION=${OPERATOR_BASE_IMAGE_VERSION} --push --pull --no-cache --builder=kiali-builder $(foreach arch,${TARGET_ARCHS},--platform=linux/${arch}) $(foreach tag,${OPERATOR_QUAY_TAG},--tag=${tag}) -f ${ROOTDIR}/build/Dockerfile ${ROOTDIR}
