.PHONY: build install clean test release help

# Binary name
BINARY=qr2fa

# Build the binary
build:
	@echo "Building $(BINARY)..."
	@go build -o $(BINARY) .
	@echo "✓ Build complete: $(BINARY)"

# Install to /usr/local/bin
install: build
	@echo "Installing $(BINARY) to /usr/local/bin..."
	@sudo mv $(BINARY) /usr/local/bin/
	@echo "✓ Installed successfully"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@rm -f $(BINARY)
	@echo "✓ Clean complete"

# Run tests
test:
	@echo "Running tests..."
	@go test -v ./...

# Build release binaries for multiple platforms
release:
	@echo "Building release binaries..."
	@mkdir -p dist
	@GOOS=darwin GOARCH=arm64 go build -o dist/$(BINARY)-darwin-arm64 .
	@GOOS=darwin GOARCH=amd64 go build -o dist/$(BINARY)-darwin-amd64 .
	@GOOS=linux GOARCH=amd64 go build -o dist/$(BINARY)-linux-amd64 .
	@echo "✓ Release builds complete in dist/"

# Generate protobuf code
proto:
	@echo "Generating protobuf code..."
	@cd internal/migration && protoc --go_out=. --go_opt=paths=source_relative migration.proto
	@echo "✓ Protobuf code generated"

# Show help
help:
	@echo "Available targets:"
	@echo "  build    - Build the binary"
	@echo "  install  - Install to /usr/local/bin"
	@echo "  clean    - Remove build artifacts"
	@echo "  test     - Run tests"
	@echo "  release  - Build release binaries for multiple platforms"
	@echo "  proto    - Generate protobuf code"
	@echo "  help     - Show this help message"
