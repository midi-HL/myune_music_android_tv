GO ?= go
BIN := bin/gdrive-pair
CMD := ./cmd/gdrive-pair

.PHONY: all test fmt vet tidy build clean cross-amd64 cross-arm64

all: test build

test:
	$(GO) test ./internal/... -count=1

fmt:
	$(GO) fmt ./...

vet:
	$(GO) vet ./internal/...

tidy:
	$(GO) mod tidy

build: tidy
	mkdir -p bin
	CGO_ENABLED=1 $(GO) build -trimpath -ldflags="-s -w" -o $(BIN) $(CMD)

cross-amd64: tidy
	go install github.com/fyne-io/fyne-cross@latest
	fyne-cross linux -arch=amd64 -app-id=com.midihl.gdrivepair $(CMD)

cross-arm64: tidy
	go install github.com/fyne-io/fyne-cross@latest
	fyne-cross linux -arch=arm64 -app-id=com.midihl.gdrivepair $(CMD)

clean:
	rm -rf bin fyne-cross
