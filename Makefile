.PHONY: test lint package install
test:
	python3 -m unittest discover -s tests -v
lint:
	python3 -m compileall -q src tests
	@if command -v qmllint >/dev/null; then qmllint contents/ui/*.qml; elif [ -x /usr/lib/qt6/bin/qmllint ]; then /usr/lib/qt6/bin/qmllint contents/ui/*.qml; else echo "qmllint unavailable; skipped"; fi
package:
	./scripts/package.sh
install:
	./scripts/install.sh
