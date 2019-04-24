.PHONY: default

default:
	docker run -d --name mysql -p 3306:3306 \
		-e MYSQL_ROOT_PASSWORD=password \
		-e MYSQL_DATABASE=wckdone mysql:5.7 | true
	docker run -d --name redis -p 6379:6379 redis:latest | true
	docker build -t wckdone:latest .
	docker run -it -v '$(shell pwd)':/wckdone \
		--link mysql:mysql \
		--link redis:redis -p 4567:4567 \
		wckdone:latest \
		sudo -Hu wckdone bash -c "cd /wckdone && /wckdone/run_dev.sh"