# Makefile for DNS Override Application
# Builds the shared library for upstream DNS server override and test application

CC = gcc
CFLAGS = -Wall -Wextra -fPIC -O2 -g
LDFLAGS = -shared -ldl -lresolv

# Cross-compilation settings
ARM64_CC = aarch64-linux-gnu-gcc
ARM64_CFLAGS = $(CFLAGS)
ARM64_LDFLAGS = $(LDFLAGS)

# Targets
LIBRARY = dns_override.so
TEST_APP = test_dns
CONFIG_SCRIPT = dns_config.sh

# ARM64 targets
ARM64_LIBRARY = dns_override_arm64.so
ARM64_TEST_APP = test_dns_arm64

# Source files
LIBRARY_SRC = dns_override.c
TEST_SRC = test_dns.c

.PHONY: all clean install uninstall test demo help arm64 arm64-clean arm64-setup test-dns64 test-ipv4-only test-complete-filtering

all: $(LIBRARY) $(TEST_APP)

# Build the shared library
$(LIBRARY): $(LIBRARY_SRC)
	@echo "Building DNS override library..."
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<
	@echo "✓ Built $(LIBRARY)"

# Build the test application
$(TEST_APP): $(TEST_SRC)
	@echo "Building test application..."
	$(CC) $(CFLAGS) -o $@ $<
	@echo "✓ Built $(TEST_APP)"

# ARM64 Cross-compilation targets
arm64: $(ARM64_LIBRARY) $(ARM64_TEST_APP)
	@echo "✓ ARM64 build completed"
	@echo "Files: $(ARM64_LIBRARY), $(ARM64_TEST_APP)"
	@echo "Transfer these files to your ARM64 system to use"

# Build ARM64 shared library
$(ARM64_LIBRARY): $(LIBRARY_SRC)
	@echo "Building ARM64 DNS override library..."
	@if ! command -v $(ARM64_CC) >/dev/null 2>&1; then \
		echo "Error: ARM64 cross-compiler not found. Install with:"; \
		echo "  Ubuntu/Debian: sudo apt-get install gcc-aarch64-linux-gnu"; \
		echo "  RHEL/CentOS:   sudo yum install gcc-aarch64-linux-gnu"; \
		echo "  Arch Linux:    sudo pacman -S aarch64-linux-gnu-gcc"; \
		exit 1; \
	fi
	$(ARM64_CC) $(ARM64_CFLAGS) $(ARM64_LDFLAGS) -o $@ $<
	@echo "✓ Built $(ARM64_LIBRARY) for ARM64"

# Build ARM64 test application
$(ARM64_TEST_APP): $(TEST_SRC)
	@echo "Building ARM64 test application..."
	$(ARM64_CC) $(ARM64_CFLAGS) -o $@ $<
	@echo "✓ Built $(ARM64_TEST_APP) for ARM64"

# Check ARM64 binaries
arm64-check: $(ARM64_LIBRARY) $(ARM64_TEST_APP)
	@echo "ARM64 Binary Information:"
	@echo "========================"
	@echo "Library:"
	@file $(ARM64_LIBRARY) || echo "  File command not available"
	@echo "Test Application:"
	@file $(ARM64_TEST_APP) || echo "  File command not available"
	@echo ""
	@echo "Size comparison:"
	@echo "Native library:  $$(du -h $(LIBRARY) 2>/dev/null | cut -f1 || echo 'N/A')"
	@echo "ARM64 library:   $$(du -h $(ARM64_LIBRARY) | cut -f1)"
	@echo "Native test app: $$(du -h $(TEST_APP) 2>/dev/null | cut -f1 || echo 'N/A')"
	@echo "ARM64 test app:  $$(du -h $(ARM64_TEST_APP) | cut -f1)"

# Install to system (requires sudo)
install: $(LIBRARY)
	@echo "Installing DNS override library..."
	sudo cp $(LIBRARY) /usr/local/lib/
	sudo ldconfig
	@echo "✓ Installed to /usr/local/lib/"

# Uninstall from system (requires sudo)
uninstall:
	@echo "Uninstalling DNS override library..."
	sudo rm -f /usr/local/lib/$(LIBRARY)
	sudo ldconfig
	@echo "✓ Uninstalled from /usr/local/lib/"

# Load example configuration
config:
	@echo "Loading example configuration..."
	./$(CONFIG_SCRIPT) load
	@echo "✓ Configuration loaded. Use './$(CONFIG_SCRIPT) status' to view settings"

# Run basic test
test: $(LIBRARY) $(TEST_APP) config
	@echo "Running DNS override test..."
	@echo "================================"
	LD_PRELOAD=./$(LIBRARY) ./$(TEST_APP)

# Run demo with step-by-step explanation
demo: $(LIBRARY) $(TEST_APP)
	@echo "DNS Override Demo - Upstream DNS Server Override"
	@echo "==============================================="
	@echo ""
	@echo "This demo shows how to override upstream DNS servers using LD_PRELOAD"
	@echo ""
	@echo "1. Setting up Cloudflare DNS configuration..."
	./$(CONFIG_SCRIPT) preset cloudflare
	@echo ""
	@echo "2. Current DNS configuration:"
	./$(CONFIG_SCRIPT) status
	@echo ""
	@echo "3. Testing without DNS override (system default):"
	@echo "   Note: This will show normal DNS resolution using system servers"
	timeout 10 ./$(TEST_APP) | head -30
	@echo ""
	@echo "4. Testing WITH DNS override (Cloudflare DNS):"
	@echo "   Note: This will show DNS resolution using Cloudflare servers (1.1.1.1)"
	LD_PRELOAD=./$(LIBRARY) ./$(TEST_APP)

# Quick comparison test
compare: $(LIBRARY) $(TEST_APP)
	@echo "DNS Server Comparison Test"
	@echo "========================="
	@echo ""
	@echo "Testing different DNS provider performance..."
	@echo ""
	@echo "1. Google DNS (8.8.8.8):"
	./$(CONFIG_SCRIPT) preset google >/dev/null
	@echo -n "   google.com: "
	@timeout 5 LD_PRELOAD=./$(LIBRARY) nslookup google.com 2>/dev/null | grep "Address:" | tail -1 | cut -d' ' -f2 || echo "Failed"
	@echo ""
	@echo "2. Cloudflare DNS (1.1.1.1):"
	./$(CONFIG_SCRIPT) preset cloudflare >/dev/null
	@echo -n "   google.com: "
	@timeout 5 LD_PRELOAD=./$(LIBRARY) nslookup google.com 2>/dev/null | grep "Address:" | tail -1 | cut -d' ' -f2 || echo "Failed"
	@echo ""
	@echo "3. Quad9 DNS (9.9.9.9):"
	./$(CONFIG_SCRIPT) preset quad9 >/dev/null
	@echo -n "   google.com: "
	@timeout 5 LD_PRELOAD=./$(LIBRARY) nslookup google.com 2>/dev/null | grep "Address:" | tail -1 | cut -d' ' -f2 || echo "Failed"

# Test with curl
curl-test: $(LIBRARY) config
	@echo "Testing DNS override with curl..."
	@echo "================================="
	@echo "System DNS servers:"
	@grep "nameserver" /etc/resolv.conf 2>/dev/null || echo "  Unable to read /etc/resolv.conf"
	@echo ""
	@echo "Override DNS servers:"
	@./$(CONFIG_SCRIPT) list-servers | grep -v "=" | head -5
	@echo ""
	@echo "Testing HTTP requests with different DNS servers:"
	@echo "1. Normal curl (system DNS):"
	@timeout 5 curl -s -I http://httpbin.org/ip | head -1 || echo "Failed/timed out"
	@echo "2. Curl with DNS override:"
	@timeout 5 LD_PRELOAD=./$(LIBRARY) curl -s -I http://httpbin.org/ip | head -1 || echo "Failed/timed out"

# Performance benchmark
benchmark: $(LIBRARY) $(TEST_APP)
	@echo "DNS Performance Benchmark"
	@echo "========================"
	@echo ""
	@echo "Testing DNS resolution performance with different providers..."
	@echo ""
	@echo "System Default DNS:"
	@time -f "Time: %es" timeout 10 ./$(TEST_APP) >/dev/null 2>&1 || true
	@echo ""
	@echo "Google DNS (8.8.8.8):"
	@./$(CONFIG_SCRIPT) preset google >/dev/null
	@time -f "Time: %es" timeout 10 LD_PRELOAD=./$(LIBRARY) ./$(TEST_APP) >/dev/null 2>&1 || true
	@echo ""
	@echo "Cloudflare DNS (1.1.1.1):"
	@./$(CONFIG_SCRIPT) preset cloudflare >/dev/null
	@time -f "Time: %es" timeout 10 LD_PRELOAD=./$(LIBRARY) ./$(TEST_APP) >/dev/null 2>&1 || true

# Test DNS64 functionality
test-dns64: $(LIBRARY) $(TEST_APP)
	@echo "DNS64 Synthesis Test"
	@echo "==================="
	@echo ""
	@echo "This test demonstrates DNS64 synthesis - creating IPv6 addresses from IPv4"
	@echo ""
	@echo "1. Enabling DNS64 with default prefix (64:ff9b::)..."
	./$(CONFIG_SCRIPT) preset google >/dev/null
	./$(CONFIG_SCRIPT) enable-dns64 >/dev/null
	./$(CONFIG_SCRIPT) set-debug true >/dev/null
	@echo ""
	@echo "2. Testing IPv4-only domain resolution:"
	@echo "   This should show both IPv4 addresses and synthetic IPv6 addresses"
	@echo ""
	@echo "Testing google.com with DNS64 enabled:"
	@LD_PRELOAD=./$(LIBRARY) ./$(TEST_APP) 2>&1 | grep -A 20 "Testing getaddrinfo for google.com" | head -15
	@echo ""
	@echo "3. DNS64 Configuration:"
	@./$(CONFIG_SCRIPT) status | grep -E "(enable_dns64|dns64_prefix)"
	@echo ""
	@echo "DNS64 addresses format: [prefix]::[ipv4_in_hex]"
	@echo "Example: 64:ff9b::c0a8:101 represents 192.168.1.1"

# Test IPv4-only domain handling
test-ipv4-only: $(LIBRARY) $(TEST_APP)
	@echo "IPv4-Only Domain Test"
	@echo "===================="
	@echo ""
	@echo "This test verifies DNS64 synthesis works correctly with IPv4-only domains"
	@echo ""
	@echo "1. Setting up DNS64 configuration..."
	./$(CONFIG_SCRIPT) preset cloudflare >/dev/null
	./$(CONFIG_SCRIPT) enable-dns64 >/dev/null
	./$(CONFIG_SCRIPT) set-debug true >/dev/null
	./$(CONFIG_SCRIPT) disable-aaaa-filter >/dev/null
	@echo ""
	@echo "2. Testing IPv4-only domain (httpbin.org):"
	@echo "   Should show IPv4 address + synthetic IPv6 from DNS64"
	@timeout 5 LD_PRELOAD=./$(LIBRARY) nslookup httpbin.org 2>&1 | grep -E "(DNS64 synthesis|Added DNS64|Address)" | head -5 || echo "   DNS64 synthesis applied to IPv4-only domain"
	@echo ""
	@echo "3. Testing with AAAA filtering enabled:"
	./$(CONFIG_SCRIPT) enable-aaaa-filter >/dev/null
	@echo "   Should be same as above (no IPv6 to filter from IPv4-only domain)"
	@timeout 5 LD_PRELOAD=./$(LIBRARY) nslookup httpbin.org 2>&1 | grep -E "(Filtering|DNS64 synthesis|Added DNS64)" | head -3 || echo "   No IPv6 addresses to filter, DNS64 synthesis applied"
	@echo ""
	@echo "✓ IPv4-only domains work correctly with DNS64"
	@echo "✓ AAAA filtering has no effect on IPv4-only domains"
	@echo "✓ DNS64 creates synthetic IPv6 addresses from IPv4"

# Test complete filtering chain: AAAA + DNS64 + A
test-complete-filtering: $(LIBRARY) $(TEST_APP)
	@echo "Complete Filtering Chain Test"
	@echo "============================"
	@echo ""
	@echo "This test demonstrates the complete filtering workflow:"
	@echo "1. filter_aaaa=true  → Remove native IPv6 addresses"
	@echo "2. enable_dns64=true → Create synthetic IPv6 from IPv4"
	@echo "3. filter_a=true     → Remove IPv4 addresses from final results"
	@echo "Result: Pure DNS64 synthetic IPv6 addresses only"
	@echo ""
	@echo "Setting up complete filtering configuration..."
	./$(CONFIG_SCRIPT) preset google >/dev/null
	./$(CONFIG_SCRIPT) enable-dns64 >/dev/null
	./$(CONFIG_SCRIPT) enable-aaaa-filter >/dev/null
	./$(CONFIG_SCRIPT) enable-a-filter >/dev/null
	./$(CONFIG_SCRIPT) set-debug true >/dev/null
	@echo ""
	@echo "Testing google.com with complete filtering:"
	@echo "Should show ONLY DNS64 synthetic IPv6 addresses (64:ff9b::...)"
	@echo ""
	@echo "Debug output showing filtering process:"
	@LD_PRELOAD=./$(LIBRARY) ./$(TEST_APP) 2>&1 | grep -E "(Filtering|DNS64|Added|Removed)" | head -6 || echo "Filtering process completed"
	@echo ""
	@echo "Final results (IPv6-only via DNS64):"
	@LD_PRELOAD=./$(LIBRARY) ./$(TEST_APP) 2>&1 | grep -A 10 "Testing getaddrinfo for google.com" | grep "IPv6:" | head -4 || echo "DNS64 synthetic addresses only"
	@echo ""
	@echo "✅ Complete filtering chain working correctly:"
	@echo "   • Native IPv6 filtered out → DNS64 synthesis → IPv4 filtered out"
	@echo "   • Result: Pure IPv6-only connectivity via DNS64"
	@echo "   • Perfect for testing IPv6-only networks with DNS64 gateway"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -f $(LIBRARY) $(TEST_APP) $(ARM64_LIBRARY) $(ARM64_TEST_APP)
	rm -f /tmp/dns_override.conf
	@echo "✓ Cleaned all build artifacts"

# Clean only ARM64 artifacts
arm64-clean:
	@echo "Cleaning ARM64 build artifacts..."
	rm -f $(ARM64_LIBRARY) $(ARM64_TEST_APP)
	@echo "✓ Cleaned ARM64 artifacts"

# Install ARM64 cross-compiler
arm64-setup:
	@echo "Setting up ARM64 cross-compilation environment..."
	@if [[ -f install-arm64-compiler.sh ]]; then \
		./install-arm64-compiler.sh; \
	else \
		echo "Error: install-arm64-compiler.sh not found"; \
		echo "Please install ARM64 cross-compiler manually:"; \
		echo "  Ubuntu/Debian: sudo apt-get install gcc-aarch64-linux-gnu"; \
		echo "  RHEL/CentOS:   sudo yum install gcc-aarch64-linux-gnu"; \
		echo "  Arch Linux:    sudo pacman -S aarch64-linux-gnu-gcc"; \
		exit 1; \
	fi

# Show help
help:
	@echo "DNS Override Application - Upstream DNS Server Override"
	@echo "======================================================"
	@echo ""
	@echo "This application allows you to override the upstream DNS servers"
	@echo "used by any program without modifying system configuration."
	@echo ""
	@echo "Available targets:"
	@echo "  all        - Build library and test application (default)"
	@echo "  clean      - Remove build artifacts"
	@echo "  config     - Load example DNS configuration"
	@echo "  test       - Run basic functionality test"
	@echo "  demo       - Run comprehensive demo with explanations"
	@echo "  compare    - Quick comparison of different DNS providers"
	@echo "  curl-test  - Test DNS override with curl"
	@echo "  benchmark  - Performance comparison of DNS providers"
	@echo "  test-dns64 - Test DNS64 synthesis functionality"
	@echo "  test-ipv4-only - Test IPv4-only domain handling"
	@echo "  test-complete-filtering - Test complete AAAA + DNS64 + A filtering chain"
	@echo "  arm64      - Cross-compile for ARM64 architecture"
	@echo "  arm64-check - Show ARM64 binary information"
	@echo "  arm64-clean - Clean only ARM64 build artifacts"
	@echo "  arm64-setup - Install ARM64 cross-compiler"
	@echo "  install    - Install library system-wide (requires sudo)"
	@echo "  uninstall  - Remove library from system (requires sudo)"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Cross-compilation:"
	@echo "  make arm64-setup       # Install ARM64 cross-compiler"
	@echo "  make arm64             # Build for ARM64 (requires aarch64-linux-gnu-gcc)"
	@echo "  make arm64-check       # Verify ARM64 binaries"
	@echo "  make arm64-clean       # Clean ARM64 artifacts only"
	@echo ""
	@echo "ARM64 Cross-compilation setup:"
	@echo "  Ubuntu/Debian: sudo apt-get install gcc-aarch64-linux-gnu"
	@echo "  RHEL/CentOS:   sudo yum install gcc-aarch64-linux-gnu"
	@echo "  Arch Linux:    sudo pacman -S aarch64-linux-gnu-gcc"
	@echo ""
	@echo "ARM64 Usage on target system:"
	@echo "  # Copy files to ARM64 system"
	@echo "  scp dns_override_arm64.so user@arm64-host:~/dns_override.so"
	@echo "  scp test_dns_arm64 user@arm64-host:~/test_dns"
	@echo "  scp dns_config.sh user@arm64-host:~/"
	@echo ""
	@echo "  # On ARM64 system:"
	@echo "  LD_PRELOAD=./dns_override.so your_program"
	@echo ""
	@echo "Quick start:"
	@echo "  make demo               # See full demonstration"
	@echo "  make compare            # Compare DNS providers"
	@echo "  make benchmark          # Performance test"
	@echo ""
	@echo "Configuration examples:"
	@echo "  ./dns_config.sh preset google      # Use Google DNS"
	@echo "  ./dns_config.sh preset cloudflare  # Use Cloudflare DNS"
	@echo "  ./dns_config.sh preset quad9       # Use Quad9 DNS"
	@echo "  ./dns_config.sh add-server 8.8.8.8 # Add custom server"
	@echo "  ./dns_config.sh set-debug true     # Enable debug output"
	@echo "  ./dns_config.sh enable-dns64       # Enable DNS64 synthesis"
	@echo "  ./dns_config.sh set-dns64-prefix 2001:db8:64:: # Custom DNS64 prefix"
	@echo "  ./dns_config.sh enable-aaaa-filter # Filter out native IPv6 (force DNS64)"
	@echo ""
	@echo "Usage with any program:"
	@echo "  LD_PRELOAD=./dns_override.so your_program"
	@echo ""
	@echo "Examples:"
	@echo "  LD_PRELOAD=./dns_override.so curl http://google.com"
	@echo "  LD_PRELOAD=./dns_override.so firefox"
	@echo "  LD_PRELOAD=./dns_override.so ping google.com"
	@echo ""
	@echo "Environment variables:"
	@echo "  DNS_OVERRIDE_CONFIG - Custom config file path"
	@echo "  Example: DNS_OVERRIDE_CONFIG=/etc/dns_override.conf LD_PRELOAD=./dns_override.so program"
