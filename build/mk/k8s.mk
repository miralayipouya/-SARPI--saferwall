KUBECTL_VER = 1.23.6
kubectl-install:		## Install kubectl.
	@kubectl version --client | grep $(KUBECTL_VER); \
		if [ $$? -eq 1 ]; then \
			curl -LOsS https://storage.googleapis.com/kubernetes-release/release/v$(KUBECTL_VER)/bin/linux/amd64/kubectl; \
			chmod +x kubectl; \
			sudo mv kubectl /usr/local/bin; \
			kubectl version --client; \
		else \
			echo "${GREEN} [*] Kubectl already installed ${RESET}"; \
		fi

KUBECTX_VER = 0.9.3
KUBECTX_URL= https://github.com/ahmetb/kubectx/releases/download/v$(KUBECTX_VER)/kubectx_v$(KUBECTX_VER)_linux_x86_64.tar.gz
k8s-kubectx-install:		## Install kubectx
	wget -N $(KUBECTX_URL) -O /tmp/kubectx.tar.gz
	tar zxvf /tmp/kubectx.tar.gz -C /tmp
	sudo mv /tmp/kubectx /usr/local/bin/
	chmod +x /usr/local/bin/kubectx
	kubectx

KUBENS_VER = 0.9.3
KUBENS_URL = https://github.com/ahmetb/kubectx/releases/download/v$(KUBENS_VER)/kubens_v$(KUBENS_VER)_linux_x86_64.tar.gz
k8s-kubens-install:			## Install Kubens
	wget -N $(KUBENS_URL) -O /tmp/kubens.tar.gz
	tar zxvf /tmp/kubens.tar.gz -C /tmp
	sudo mv /tmp/kubens /usr/local/bin/
	chmod +x /usr/local/bin/kubens
	kubens

KUBE_CAPACITY_VER = 0.5.0
k8s-kube-capacity: 	## Install kube-capacity
	wget https://github.com/robscott/kube-capacity/releases/download/$(KUBE_CAPACITY_VER)/kube-capacity_$(KUBE_CAPACITY_VER)_Linux_x86_64.tar.gz -P /tmp
	cd /tmp \
		&& tar zxvf kube-capacity_$(KUBE_CAPACITY_VER)_Linux_x86_64.tar.gz \
		&& sudo mv kube-capacity /usr/local/bin \
		&& kube-capacity

k8s-prepare:	k8s-kubectl-install k8s-kube-capacity k8s-minikube-start ## Install minikube, kubectl, kube-capacity and start a cluster

k8s-pf-kibana:			## Port fordward Kibana
	kubectl port-forward svc/$(SAFERWALL_RELEASE_NAME)-kibana 5601:5601 --address='0.0.0.0' &
	while true ; do nc -vz 127.0.0.1 5601 ; sleep 5 ; done

k8s-pf-nsq:				## Port fordward NSQ admin service.
	kubectl port-forward svc/$(SAFERWALL_RELEASE_NAME)-nsqadmin 4171:4171 --address='0.0.0.0' &
	while true ; do nc -vz 127.0.0.1 4171 ; sleep 5 ; done

k8s-pf-grafana:			## Port fordward grafana dashboard service.
	kubectl port-forward deployment/$(SAFERWALL_RELEASE_NAME)-grafana 3000:3000 --address='0.0.0.0' &
	while true ; do nc -vz 127.0.0.1 3000 ; sleep 5 ; done

k8s-pf-couchbase:		## Port fordward couchbase ui service.
	kubectl port-forward svc/couchbase-cluster-ui 8091:8091 --address='0.0.0.0' &
	while true ; do nc -vz 127.0.0.1 8091 ; sleep 5 ; done

k8s-pf:					## Port forward all services.
	make k8s-pf-nsq &
	make k8s-pf-couchbase &
	make k8s-pf-grafana &
	make k8s-pf-kibana &

k8s-delete-all-objects: ## Delete all objects
	kubectl delete "$(kubectl api-resources --namespaced=true --verbs=delete -o name | tr "\n" "," | sed -e 's/,$//')" --all

k8s-dump-tls-secrets: ## Dump TLS secrets
	sudo apt install jq -y
	$(eval HELM_RELEASE_NAME := $(shell sudo helm ls --filter saferwall --output json | jq '.[0].name' | tr -d '"'))
	$(eval HELM_SECRET_TLS_NAME := $(HELM_RELEASE_NAME)-tls)
	kubectl get secret $(HELM_SECRET_TLS_NAME) -o jsonpath="{.data['ca\.crt']}" | base64 --decode  >> ca.crt
	kubectl get secret $(HELM_SECRET_TLS_NAME) -o jsonpath="{.data['tls\.crt']}" | base64 --decode  >> tls.crt
	kubectl get secret $(HELM_SECRET_TLS_NAME) -o jsonpath="{.data['tls\.key']}" | base64 --decode  >> tls.key
	openssl pkcs12 -export -out saferwall.p12 -inkey tls.key -in tls.crt -certfile ca.crt

CERT_MANAGER_VER=1.8.0
k8s-init-cert-manager: ## Init cert-manager
	# Install the chart.
	helm install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--version v$(CERT_MANAGER_VER) \
		--set installCRDs=true
	# Verify the installation.
	kubectl wait --namespace cert-manager \
	--for=condition=ready pod \
	--selector=app.kubernetes.io/instance=cert-manager \
	--timeout=90s

k8s-install-couchbase-crds:
	kubectl apply -f https://raw.githubusercontent.com/couchbase-partners/helm-charts/master/charts/couchbase-operator/crds/couchbase.crds.yaml

k8s-cert-manager-rm-crd: ## Delete cert-manager crd objects.
	kubectl get crd | grep cert-manager | xargs --no-run-if-empty kubectl delete crd
	kubectl delete namespace cert-manager

k8s-events: ## Get Kubernetes cluster events.
	kubectl get events --sort-by='.metadata.creationTimestamp'

k8s-delete-terminating-pods: ## Force delete pods stuck at `Terminating` status
	for p in $$(kubectl get pods | grep Terminating | awk '{print $$1}'); \
	 do kubectl delete pod $$p --grace-period=0 --force;done

k8s-delete-evicted-pods:	## Clean up all evicted pods
	kubectl get pods | grep Evicted | awk '{print $$1}' | xargs kubectl delete pod
