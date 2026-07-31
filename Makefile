.PHONY: enterprise-up enterprise-base enterprise-provision enterprise-seed enterprise-policy enterprise-verify enterprise-all enterprise-ansible enterprise-ansible-syntax enterprise-snapshot enterprise-reset

ENTERPRISE_PROFILE ?= team
ENTERPRISE_SNAPSHOT ?= enterprise-ready

enterprise-up:
	bash lab-scripts/enterprise-deploy.sh --phase infra --profile $(ENTERPRISE_PROFILE)

enterprise-base:
	bash lab-scripts/enterprise-deploy.sh --phase base --profile $(ENTERPRISE_PROFILE)

enterprise-provision:
	bash lab-scripts/enterprise-deploy.sh --phase provision --profile $(ENTERPRISE_PROFILE)

enterprise-seed:
	bash lab-scripts/enterprise-deploy.sh --phase seed --profile $(ENTERPRISE_PROFILE)

enterprise-policy:
	bash lab-scripts/enterprise-deploy.sh --phase policy --profile $(ENTERPRISE_PROFILE)

enterprise-verify:
	bash lab-scripts/enterprise-verify.sh --profile $(ENTERPRISE_PROFILE)

enterprise-all:
	bash lab-scripts/enterprise-deploy.sh --phase all --profile $(ENTERPRISE_PROFILE)

enterprise-ansible:
	bash lab-scripts/enterprise-deploy-ansible.sh --phase all --profile $(ENTERPRISE_PROFILE)

enterprise-ansible-syntax:
	@if ! command -v ansible-playbook >/dev/null 2>&1; then \
		echo "ansible-playbook not found; install ansible-core or Ansible first"; \
		exit 2; \
	fi
	@tmp_dir=$$(mktemp -d); \
	trap 'rm -rf "$$tmp_dir"' EXIT; \
	bash lab-scripts/enterprise-generate-ansible-inventory.sh --profile team > "$$tmp_dir/team.yml"; \
	bash lab-scripts/enterprise-generate-ansible-inventory.sh --profile pro > "$$tmp_dir/pro.yml"; \
	ansible-playbook -i "$$tmp_dir/team.yml" lab-scripts/ansible/enterprise.yml --syntax-check; \
	ansible-playbook -i "$$tmp_dir/pro.yml" lab-scripts/ansible/enterprise.yml --syntax-check

enterprise-snapshot:
	bash lab-scripts/enterprise-snapshots.sh create $(ENTERPRISE_SNAPSHOT)

enterprise-reset:
	bash lab-scripts/enterprise-reset.sh $(ENTERPRISE_SNAPSHOT)
