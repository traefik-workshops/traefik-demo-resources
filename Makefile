VERSION := $(shell git tag --list 'v*' | sort -V | tail -n1 2>/dev/null || echo "v0.0.0")

.PHONY: bump_major bump_minor bump_patch release

# Helper to bump version
# Usage: make bump_part PART=major|minor|patch
bump_part:
	@current_tag=$$(git tag --list 'v*' | sort -V | tail -n1 2>/dev/null || echo "v0.0.0"); \
	version_num=$${current_tag#v}; \
	IFS='.' read -r major minor patch <<< "$$version_num"; \
	if [ "$(PART)" = "major" ]; then \
		major=$$((major + 1)); minor=0; patch=0; \
	elif [ "$(PART)" = "minor" ]; then \
		minor=$$((minor + 1)); patch=0; \
	elif [ "$(PART)" = "patch" ]; then \
		patch=$$((patch + 1)); \
	fi; \
	new_tag="v$$major.$$minor.$$patch"; \
	echo "Bumping $$current_tag -> $$new_tag"; \
	git tag $$new_tag; \
	echo "Tag $$new_tag created. Run 'make release' to push."

bump_major:
	$(MAKE) bump_part PART=major

bump_minor:
	$(MAKE) bump_part PART=minor

bump_patch:
	$(MAKE) bump_part PART=patch

release:
	@echo "Pushing git tags..."
	git push origin --tags

publish-charts:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make publish-charts VERSION=0.1.0"; \
		exit 1; \
	fi
	@echo "Packaging and publishing charts version $(VERSION)..."
	@charts="ai-gateway/helm airlines/helm chats/helm dns-traefiker/helm presidio/helm"; \
	for chart in $$charts; do \
		chart_name=$$(basename $$(dirname $$chart)); \
		echo "Processing $$chart_name..."; \
		package_output=$$(helm package $$chart --version $(VERSION) --app-version $(VERSION)); \
		package_file=$$(basename $$(echo "$$package_output" | grep -oE '[^ ]+\.tgz$$')); \
		echo "Package file: $$package_file"; \
		echo "Pushing $$package_file to ghcr.io/traefik-workshops..."; \
		helm push $$package_file oci://ghcr.io/traefik-workshops; \
		echo "✓ Published $$chart_name version $(VERSION)"; \
	done
	@echo ""
	@echo "All charts published successfully!"
	@echo "Charts are available at: oci://ghcr.io/traefik-workshops/<chart-name>:$(VERSION)"


