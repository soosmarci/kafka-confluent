# User manual

## push config change for one component that is running in doccker

```bash
docker-compose restart control-center
```

## stops and removes containers and default networks created by up
## volumes: kept
```bash
docker compose down
```

## Eliminate Unnamed Volumes: This will remove anonymous local volumes not used by at least one container
```bash
docker volume prune
```

## stops and removes containers and default networks created by up
## --volumes: remove ALL volumes (named, unnamed)
```bash
docker compose down --volumes
```