ping:
	ansible all -m ping -i datainc/inventory.yml

up:
	ansible-playbook -i datainc/inventory.yml datainc/main.yml -e @datainc/extra-vars.yml

seed-data:
	aws s3 cp ../datainc/data/raw/dev/ s3://lakehouse/raw/dev/ --recursive --profile datanuggets-garage --no-verify-ssl
