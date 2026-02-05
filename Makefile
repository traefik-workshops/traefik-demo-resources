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
