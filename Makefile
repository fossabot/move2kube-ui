#   Copyright IBM Corporation 2023
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

BINNAME     ?= move2kube-ui
REGISTRYNS  := quay.io/konveyor
DISTDIR     := $(CURDIR)/build

GIT_COMMIT = $(shell git rev-parse HEAD)
GIT_SHA    = $(shell git rev-parse --short HEAD)
GIT_TAG    = $(shell git tag --points-at | tail -n 1)
GIT_DIRTY  = $(shell test -n "`git status --porcelain`" && echo "dirty" || echo "clean")

MULTI_ARCH_TARGET_PLATFORMS := linux/arm64,linux/amd64

ifdef VERSION
	BINARY_VERSION = $(VERSION)
endif
BINARY_VERSION ?= ${GIT_TAG}
ifneq ($(BINARY_VERSION),)
	VERSION ?= $(BINARY_VERSION)
endif

VERSION ?= latest

VERSION_METADATA = unreleased
ifneq ($(GIT_TAG),)
	VERSION_METADATA =
endif

# Setting container tool
DOCKER_CMD := $(shell command -v docker 2> /dev/null)
PODMAN_CMD := $(shell command -v podman 2> /dev/null)

ifdef DOCKER_CMD
	CONTAINER_TOOL = 'docker'
else ifdef PODMAN_CMD
	CONTAINER_TOOL = 'podman'
endif

# HELP
# This will output the help for each task
.PHONY: help
help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[0-9a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: clean
clean:
	rm -rf $(DISTDIR)

.PHONY: install
install: ## Install dependencies
	@pnpm install

.PHONY: build
build: ## Build application
	@pnpm run build

.PHONY: start
start: install build ## Start server
	@pnpm run start-api

# -- Container Runtime --

.PHONY: cbuild
cbuild: ## Build container image	
ifndef CONTAINER_TOOL
	$(error No container tool (docker, podman) found in your environment. Please, install one)
endif
	@echo "Building image with $(CONTAINER_TOOL)"
	${CONTAINER_TOOL} build -t ${REGISTRYNS}/${BINNAME}-builder:${VERSION} --cache-from ${REGISTRYNS}/${BINNAME}-builder:latest --target build_base                             --build-arg VERSION=${VERSION} .
	${CONTAINER_TOOL} tag ${REGISTRYNS}/${BINNAME}-builder:${VERSION} ${REGISTRYNS}/${BINNAME}-builder:latest
	${CONTAINER_TOOL} build -t ${REGISTRYNS}/${BINNAME}:${VERSION}         --cache-from ${REGISTRYNS}/${BINNAME}-builder:latest --cache-from ${REGISTRYNS}/${BINNAME}:latest    --build-arg VERSION=${VERSION} --build-arg "MOVE2KUBE_UI_GIT_COMMIT_HASH=${GIT_COMMIT}" --build-arg "MOVE2KUBE_UI_GIT_TREE_STATUS=${GIT_DIRTY}" .
	${CONTAINER_TOOL} tag ${REGISTRYNS}/${BINNAME}:${VERSION} ${REGISTRYNS}/${BINNAME}:latest

.PHONY: cpush
cpush: ## Push container image
ifndef CONTAINER_TOOL
	$(error No container tool (docker, podman) found in your environment. Please, install one)
endif
	@echo "Pushing image with $(CONTAINER_TOOL)"
	# To help with reusing layers and hence speeding up build
	${CONTAINER_TOOL} push ${REGISTRYNS}/${BINNAME}-builder:${VERSION}
	${CONTAINER_TOOL} push ${REGISTRYNS}/${BINNAME}:${VERSION}

.PHONY: crun
crun: ## Run using container image
ifndef CONTAINER_TOOL
	$(error No container tool (docker, podman) found in your environment. Please, install one)
endif
	@echo "Running image with $(CONTAINER_TOOL)"	
ifdef DOCKER_CMD
	${CONTAINER_TOOL} run --rm -it -p 8080:8080 -v ${PWD}/data:/move2kube-api/data -v /var/run/docker.sock:/var/run/docker.sock quay.io/konveyor/move2kube-ui:latest
else
	${CONTAINER_TOOL} run --rm -it -p 8080:8080 -v ${PWD}/data:/move2kube-api/data:z --network=bridge quay.io/konveyor/move2kube-ui:latest
endif

.PHONY: prepare-for-release
prepare-for-release:
	mv helm-charts/move2kube/Chart.yaml old
	cat old | sed -E s/version:\ v0.1.0-unreleased/version:\ ${IMAGE_TAG}/ | sed -E s/appVersion:\ latest/appVersion:\ ${IMAGE_TAG}/ > helm-charts/move2kube/Chart.yaml
	rm old

.PHONY: cmultibuildpush
cmultibuildpush: ## Build and push multi arch container image
ifndef DOCKER_CMD
	$(error Docker wasn't detected. Please install docker and try again.)
endif
	@echo "Building image for multiple architectures with $(CONTAINER_TOOL)"

	## TODO: When docker exporter supports exporting manifest lists we can separate out this into two steps: build and push

	${CONTAINER_TOOL} buildx create --name m2k-builder --driver-opt network=host --use --platform ${MULTI_ARCH_TARGET_PLATFORMS}

	${CONTAINER_TOOL} buildx build --platform ${MULTI_ARCH_TARGET_PLATFORMS} --tag ${REGISTRYNS}/${BINNAME}-builder:${VERSION} --tag ${REGISTRYNS}/${BINNAME}-builder:latest --cache-from ${REGISTRYNS}/${BINNAME}-builder:latest --target build_base --build-arg VERSION=${VERSION} --push .;
	${CONTAINER_TOOL} buildx build --platform ${MULTI_ARCH_TARGET_PLATFORMS} --tag ${REGISTRYNS}/${BINNAME}:${VERSION} --tag ${REGISTRYNS}/${BINNAME}:latest --cache-from ${REGISTRYNS}/${BINNAME}-builder:latest --cache-from ${REGISTRYNS}/${BINNAME}:latest --build-arg VERSION=${VERSION} --build-arg "MOVE2KUBE_UI_GIT_COMMIT_HASH=${GIT_COMMIT}" --build-arg "MOVE2KUBE_UI_GIT_TREE_STATUS=${GIT_DIRTY}" --push .;

	${CONTAINER_TOOL} buildx rm m2k-builder