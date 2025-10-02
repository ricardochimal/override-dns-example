# DNS Override Application - Upstream DNS Server Override

This application allows you to override the upstream DNS servers used by any program without modifying system configuration files. It uses `LD_PRELOAD` to intercept DNS resolution functions and redirect queries to your chosen DNS servers.

## Features

- **Upstream DNS Override**: Redirect DNS queries to custom DNS servers (Google, Cloudflare, Quad9, etc.)
- **DNS64 Support**: Automatic synthesis of IPv6 addresses from IPv4 addresses for IPv6-only networks
- **Multiple DNS Providers**: Built-in presets for popular DNS services
- **Performance Testing**: Compare DNS server performance
- **Debug Mode**: See which DNS servers are being used and DNS64 synthesis
- **Easy Configuration**: Simple command-line configuration management
- **Works with Any Program**: Use with curl, browsers, ping, or any network application

## Quick Start

1. **Build the application:**
   ```bash
   make
   ```

2. **Set up DNS servers:**
   ```bash
   # Use Cloudflare DNS (1.1.1.1)
   ./dns_config.sh preset cloudflare
   
   # Or use Google DNS (8.8.8.8)
   ./dns_config.sh preset google
   ```

3. **Test with any program:**
   ```bash
   # Test with the included test application
   LD_PRELOAD=./dns_override.so ./test_dns
   
   # Test with curl
   LD_PRELOAD=./dns_override.so curl http://google.com
   
   # Test with any other program
   LD_PRELOAD=./dns_override.so your_program
   ```

## How It Works

The application intercepts the following DNS resolution functions:
- `gethostbyname()` - Traditional hostname resolution
- `getaddrinfo()` - Modern address resolution (supports IPv4/IPv6)

When these functions are called, the library:
1. Loads your custom DNS server configuration
2. Modifies the system resolver state temporarily
3. Performs the DNS query using your specified servers
4. Restores the original resolver state
5. Returns the results to the calling program

## Configuration

### DNS Provider Presets

Use built-in presets for popular DNS services:

```bash
# Google DNS (8.8.8.8, 8.8.4.4)
./dns_config.sh preset google

# Cloudflare DNS (1.1.1.1, 1.0.0.1) - Fast and privacy-focused
./dns_config.sh preset cloudflare

# Quad9 DNS (9.9.9.9) - Blocks malicious domains
./dns_config.sh preset quad9

# OpenDNS (208.67.222.222, 208.67.220.220) - Content filtering
./dns_config.sh preset opendns

# AdGuard DNS (94.140.14.14) - Blocks ads and trackers
./dns_config.sh preset adguard
```

### Custom Configuration

```bash
# Add custom DNS servers
./dns_config.sh add-server 8.8.8.8:53
./dns_config.sh add-server 1.1.1.1

# Configure timeout (in milliseconds)
./dns_config.sh set-timeout 3000

# Enable TCP mode (instead of UDP)
./dns_config.sh set-tcp true

# Enable debug output
./dns_config.sh set-debug true

# Enable DNS64 synthesis for IPv6-only networks
./dns_config.sh enable-dns64

# Set custom DNS64 prefix (default: 64:ff9b::)
./dns_config.sh set-dns64-prefix 2001:db8:64::

# View current configuration
./dns_config.sh status

# List configured servers
./dns_config.sh list-servers
```

### DNS64 Configuration

DNS64 is a mechanism that creates synthetic IPv6 addresses from IPv4 addresses, useful for IPv6-only networks accessing IPv4-only services:

```bash
# Enable DNS64 synthesis
./dns_config.sh enable-dns64

# Set custom DNS64 prefix (RFC 6052 well-known prefix)
./dns_config.sh set-dns64-prefix 64:ff9b::

# Alternative prefixes:
./dns_config.sh set-dns64-prefix 2001:db8:64::    # Documentation prefix
./dns_config.sh set-dns64-prefix fd00:64::        # Local prefix

# Filter out native IPv6 addresses (force DNS64 only)
./dns_config.sh enable-aaaa-filter

# Allow both native IPv6 and DNS64 addresses (default)
./dns_config.sh disable-aaaa-filter

# Test DNS64 functionality
./dns_config.sh test-dns64
make test-dns64

# Disable DNS64
./dns_config.sh disable-dns64
```

#### AAAA Record Filtering

The AAAA filtering feature removes native IPv6 addresses from DNS responses before DNS64 synthesis, forcing all IPv6 traffic through the DNS64 gateway:

```bash
# Enable AAAA filtering - removes native IPv6 addresses
./dns_config.sh enable-aaaa-filter

# Result: Only IPv4 + DNS64 synthetic IPv6 addresses
# Before: IPv4: 1.2.3.4, IPv6: 2001:db8::1, DNS64: 64:ff9b::102:304
# After:  IPv4: 1.2.3.4, DNS64: 64:ff9b::102:304

# Disable AAAA filtering - preserves native IPv6 addresses  
./dns_config.sh disable-aaaa-filter

# Result: IPv4 + native IPv6 + DNS64 synthetic IPv6 addresses
```

**Use Cases for AAAA Filtering:**
- **IPv6-only network testing** - Simulate pure IPv6-only environment
- **DNS64 gateway enforcement** - Force all traffic through DNS64 infrastructure
- **Transition testing** - Test applications with only synthetic IPv6 addresses
- **Performance comparison** - Compare native IPv6 vs DNS64 performance

### Configuration File Format

The configuration is stored in `/tmp/dns_override.conf` by default, but can be customized using the `DNS_OVERRIDE_CONFIG` environment variable:

```bash
# Use default location
LD_PRELOAD=./dns_override.so your_program

# Use custom config file location
export DNS_OVERRIDE_CONFIG=/etc/dns_override.conf
LD_PRELOAD=./dns_override.so your_program

# Or inline
DNS_OVERRIDE_CONFIG=~/.config/dns_override.conf LD_PRELOAD=./dns_override.so your_program
```

Configuration file format:

```
# DNS servers (IP:PORT format, port optional)
dns_server 1.1.1.1:53
dns_server 1.0.0.1:53

# Timeout in milliseconds
timeout 5000

# Use TCP instead of UDP
use_tcp false

# Enable debug output
debug true

# DNS64 configuration
enable_dns64 true
dns64_prefix 64:ff9b::
filter_aaaa false
```

## Testing and Demos

### Run Full Demo
```bash
make demo
```
Shows step-by-step comparison between system DNS and custom DNS servers.

### Compare DNS Providers
```bash
make compare
```
Quick comparison of different DNS provider performance.

### Performance Benchmark
```bash
make benchmark
```
Detailed performance comparison with timing information.

### Test with curl
```bash
make curl-test
```
Test HTTP requests with different DNS configurations.

### Test DNS64 Synthesis
```bash
make test-dns64
```
Test DNS64 functionality and see synthetic IPv6 addresses created from IPv4.

### Manual Testing
```bash
# Test the included application
./dns_config.sh preset cloudflare
./dns_config.sh enable-dns64
LD_PRELOAD=./dns_override.so ./test_dns

# Compare with system default
./test_dns  # Without LD_PRELOAD
```

## Real-World Usage Examples

### Web Browsing with Custom DNS
```bash
# Use Cloudflare DNS with Firefox
./dns_config.sh preset cloudflare
LD_PRELOAD=./dns_override.so firefox

# Use AdGuard DNS to block ads
./dns_config.sh preset adguard
LD_PRELOAD=./dns_override.so chromium
```

### Custom Configuration Locations
```bash
# System-wide configuration
export DNS_OVERRIDE_CONFIG=/etc/dns_override.conf
sudo ./dns_config.sh preset cloudflare
LD_PRELOAD=./dns_override.so your_program

# User-specific configuration
export DNS_OVERRIDE_CONFIG=~/.config/dns_override.conf
./dns_config.sh preset google
LD_PRELOAD=./dns_override.so your_program

# Project-specific configuration
DNS_OVERRIDE_CONFIG=./project-dns.conf ./dns_config.sh preset quad9
DNS_OVERRIDE_CONFIG=./project-dns.conf LD_PRELOAD=./dns_override.so your_program
```

### IPv6-Only Network Support with DNS64
```bash
# Configure for IPv6-only network environment
./dns_config.sh preset cloudflare
./dns_config.sh enable-dns64
./dns_config.sh set-dns64-prefix 64:ff9b::

# Option 1: Keep native IPv6 addresses (default)
./dns_config.sh disable-aaaa-filter
# Result: Both native IPv6 and DNS64 synthetic addresses available

# Option 2: Force DNS64 only (filter out native IPv6)
./dns_config.sh enable-aaaa-filter  
# Result: Only IPv4 and DNS64 synthetic addresses available

# Access IPv4-only services from IPv6-only network
LD_PRELOAD=./dns_override.so curl http://ipv4-only-service.com
LD_PRELOAD=./dns_override.so ssh user@ipv4-server.example.com

# The application will automatically create synthetic IPv6 addresses
# Example: 192.168.1.1 becomes 64:ff9b::c0a8:101
```

### Development and Testing
```bash
# Test API endpoints with different DNS
./dns_config.sh preset google
LD_PRELOAD=./dns_override.so curl -v https://api.example.com

# Debug DNS resolution issues
./dns_config.sh set-debug true
LD_PRELOAD=./dns_override.so your_application
```

### Network Troubleshooting
```bash
# Test connectivity with different DNS servers
./dns_config.sh preset quad9
LD_PRELOAD=./dns_override.so ping google.com

# Compare DNS response times
./dns_config.sh test
```

## Installation

### System-wide Installation (Optional)
```bash
# Install library to /usr/local/lib
sudo make install

# Now you can use it without specifying the full path
LD_PRELOAD=dns_override.so your_program

# Uninstall
sudo make uninstall
```

### Permanent Configuration
To make DNS override permanent for a user, add to `~/.bashrc`:
```bash
export LD_PRELOAD="/path/to/dns_override.so:$LD_PRELOAD"
```

## Troubleshooting

### Debug Mode
Enable debug output to see what's happening:
```bash
./dns_config.sh set-debug true
LD_PRELOAD=./dns_override.so your_program
```

### Common Issues

1. **Library not found**: Make sure `dns_override.so` exists and is in the current directory
2. **Permission denied**: Ensure the library file is executable
3. **No effect**: Some programs may use alternative DNS resolution methods
4. **Slow resolution**: Try different DNS servers or increase timeout

### Verify It's Working
```bash
# Check that override is active
LD_PRELOAD=./dns_override.so ./test_dns

# Compare with system default
./test_dns
```

## Limitations

- Only intercepts standard C library DNS functions (`gethostbyname`, `getaddrinfo`)
- Some programs may use alternative DNS resolution methods
- Does not affect programs that make direct DNS queries (like `dig`)
- IPv6 support depends on the configured DNS servers

## Building from Source

### Requirements
- GCC compiler
- Standard C library development headers
- Make

### Build Process
```bash
# Build everything
make

# Build only the library
make dns_override.so

# Build only the test application
make test_dns

# Clean build artifacts
make clean
```

### ARM64 Cross-Compilation

Build for ARM64 systems (Apple Silicon Macs, ARM servers, Raspberry Pi):

```bash
# Install ARM64 cross-compiler (automated)
make arm64-setup

# Or install manually:
# Ubuntu/Debian: sudo apt-get install gcc-aarch64-linux-gnu
# RHEL/CentOS:   sudo yum install gcc-aarch64-linux-gnu  
# Arch Linux:    sudo pacman -S aarch64-linux-gnu-gcc

# Build for ARM64
make arm64

# Verify ARM64 binaries
make arm64-check

# Clean ARM64 artifacts
make arm64-clean
```

**Transfer to ARM64 system:**
```bash
# Copy files to ARM64 target
scp dns_override_arm64.so user@arm64-host:~/dns_override.so
scp test_dns_arm64 user@arm64-host:~/test_dns
scp dns_config.sh user@arm64-host:~/

# Use on ARM64 system
ssh user@arm64-host
LD_PRELOAD=./dns_override.so your_program
```

### Build Options
The Makefile supports several build configurations:
- Debug builds with `-g` flag
- Optimized builds with `-O2` flag
- Warning flags for code quality

## Technical Details

### Intercepted Functions
- `gethostbyname()` - IPv4 hostname resolution
- `getaddrinfo()` - Modern address resolution (IPv4/IPv6)

### Implementation
- Uses `dlsym(RTLD_NEXT, ...)` to get original function pointers
- Modifies `_res` resolver state temporarily
- Preserves original resolver configuration
- Thread-safe implementation

### Configuration Loading
- Configuration loaded on first DNS query
- Cached for subsequent queries
- Supports runtime reconfiguration

## License

This project is released under the MIT License. See the source code for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Support

For questions and support, please check the documentation or create an issue in the project repository.
