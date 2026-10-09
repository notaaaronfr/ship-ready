# One-command developer workflow. Python example; swap commands for your stack.
.PHONY: setup run fmt lint test bench check clean

setup:
	pip install -e ".[dev]"
	pre-commit install

run:
	python -m app

fmt:
	ruff format .
	ruff check --fix .

lint:
	ruff format --check .
	ruff check .
	mypy --strict src

test:
	pytest --cov=src --cov-branch --cov-report=term-missing --cov-fail-under=80

bench:
	pytest tests/bench --benchmark-only

check: lint test
	bandit -q -r src
	pip-audit

clean:
	rm -rf .pytest_cache .mypy_cache .ruff_cache .coverage htmlcov dist build
