# solyto deployment

Ansible playbooks for deploying Solyto services to production.

## Structure

```
playbooks/        # One playbook per service
inventory/
  production/
    hosts.ini           # Your actual server inventory (gitignored)
    hosts.ini.example   # Template to copy from
    group_vars/         # Per-service variables
templates/        # Jinja2 templates for compose files, Dockerfiles, .env files
```

## Requirements

- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html)

## Setup

Copy the inventory example and fill in your server details:

```sh
cp inventory/production/hosts.ini.example inventory/production/hosts.ini
```

Edit `hosts.ini` and set `ansible_user` and `ansible_ssh_private_key_file`.

## Deploying

Each service can be deployed independently:

```sh
make deploy-api
make deploy-app
make deploy-landing-page
make deploy-db
```

Or run a playbook directly:

```sh
ansible-playbook playbooks/api.yml
```

The default inventory points to `inventory/production`, so no `-i` flag needed.
