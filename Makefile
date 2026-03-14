ping:
	ansible all -m ping -i datainc/inventory.yml

up:
	ansible-playbook -i datainc/inventory.yml datainc/main.yml -e @datainc/extra-vars.yml

postgres-up:
	ansible-playbook -i inventory.yml psql-playbook.yaml -e @extra-vars.yml
