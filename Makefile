.PHONY: help obs-up obs-down obs-logs obs-reset

help:
	@echo "Available targets:"
	@echo "  obs-up     Start observability stack (Prometheus/Alertmanager/Grafana)"
	@echo "  obs-down   Stop observability stack"
	@echo "  obs-logs   Tail logs for observability services"
	@echo "  obs-reset  Stop stack and remove observability volumes"

obs-up:
	docker compose -f docker-compose.observability.yml up -d

obs-down:
	docker compose -f docker-compose.observability.yml down

obs-logs:
	docker compose -f docker-compose.observability.yml logs -f

obs-reset:
	docker compose -f docker-compose.observability.yml down -v
