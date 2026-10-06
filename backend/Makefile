.PHONY: run test tidy smoke
run:
	go run ./cmd/server
test:
	go test ./...
tidy:
	go mod tidy
smoke:
	python3 scripts/smoke_test.py http://localhost:8080
