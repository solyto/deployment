deploy-api:
	ansible-playbook playbooks/api.yml

deploy-app:
	ansible-playbook playbooks/app.yml

deploy-landing-page:
	ansible-playbook playbooks/landing-page.yml

deploy-db:
	ansible-playbook playbooks/db.yml

deploy-docs:
	ansible-playbook playbooks/docs.yml

deploy:
	make deploy-api
	make deploy-app