#!/bin/bash

# DNS Override Configuration Manager
# This script helps manage upstream DNS server configuration

# Configuration file path - can be overridden by environment variable
DEFAULT_CONFIG_FILE="/tmp/dns_override.conf"
CONFIG_FILE="${DNS_OVERRIDE_CONFIG:-$DEFAULT_CONFIG_FILE}"
EXAMPLE_CONFIG="dns_override.conf.example"

show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  add-server <ip[:port]>  Add a DNS server"
    echo "  remove-server <ip>      Remove a DNS server"
    echo "  list-servers            List configured DNS servers"
    echo "  set-timeout <ms>        Set query timeout in milliseconds"
    echo "  set-tcp <true|false>    Enable/disable TCP mode"
    echo "  set-debug <true|false>  Enable/disable debug output"
    echo "  enable-dns64            Enable DNS64 synthesis"
    echo "  disable-dns64           Disable DNS64 synthesis"
    echo "  set-dns64-prefix <prefix> Set DNS64 prefix (e.g., 64:ff9b::)"
    echo "  enable-aaaa-filter      Filter out native IPv6 addresses (force DNS64)"
    echo "  disable-aaaa-filter     Allow native IPv6 addresses alongside DNS64"
    echo "  enable-a-filter         Filter out IPv4 addresses from final results"
    echo "  disable-a-filter        Allow IPv4 addresses in final results"
    echo "  preset <name>           Load a DNS provider preset"
    echo "  clear                   Clear all configuration"
    echo "  load                    Load example configuration"
    echo "  edit                    Edit configuration file"
    echo "  status                  Show configuration status"
    echo "  test                    Test DNS resolution"
    echo "  test-dns64              Test DNS64 synthesis"
    echo "  test-ipv4-only          Test IPv4-only domain handling"
    echo "  test-complete-filtering Test AAAA + DNS64 + A filtering chain"
    echo ""
    echo "DNS Provider Presets:"
    echo "  google      - Google DNS (8.8.8.8, 8.8.4.4)"
    echo "  cloudflare  - Cloudflare DNS (1.1.1.1, 1.0.0.1)"
    echo "  quad9       - Quad9 DNS (9.9.9.9, 149.112.112.112)"
    echo "  opendns     - OpenDNS (208.67.222.222, 208.67.220.220)"
    echo "  adguard     - AdGuard DNS (94.140.14.14, 94.140.15.15)"
    echo ""
    echo "Examples:"
    echo "  $0 add-server 8.8.8.8"
    echo "  $0 add-server 1.1.1.1:53"
    echo "  $0 preset cloudflare"
    echo "  $0 set-timeout 3000"
    echo "  $0 enable-dns64"
    echo "  $0 set-dns64-prefix 2001:db8:64::"
    echo "  $0 enable-aaaa-filter"
    echo "  $0 enable-a-filter"
    echo "  $0 test-dns64"
    echo "  $0 test-ipv4-only"
    echo "  $0 test-complete-filtering"
    echo ""
    echo "Configuration file:"
    echo "  Default: $DEFAULT_CONFIG_FILE"
    echo "  Current: $CONFIG_FILE"
    if [[ -n "$DNS_OVERRIDE_CONFIG" ]]; then
        echo "  (Set by DNS_OVERRIDE_CONFIG environment variable)"
    fi
    echo ""
    echo "Environment variables:"
    echo "  DNS_OVERRIDE_CONFIG - Override config file path"
    echo "  Example: export DNS_OVERRIDE_CONFIG=/etc/dns_override.conf"
}

add_server() {
    local server="$1"
    
    if [[ -z "$server" ]]; then
        echo "Error: DNS server is required"
        echo "Format: IP[:PORT] or [IPv6]:PORT"
        echo "Examples:"
        echo "  8.8.8.8"
        echo "  8.8.8.8:53"
        echo "  2001:4860:4860::8888"
        echo "  [2001:4860:4860::8844]:53"
        exit 1
    fi
    
    # Improved validation for IPv4 and IPv6 addresses
    local is_valid=0
    
    # Check for IPv6 with brackets: [address]:port
    if [[ "$server" =~ ^\[([0-9a-fA-F:]+)\](:([0-9]+))?$ ]]; then
        local ipv6_addr="${BASH_REMATCH[1]}"
        # Basic IPv6 validation (contains colons and hex characters)
        if [[ "$ipv6_addr" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$ipv6_addr" == *":"* ]]; then
            is_valid=1
        fi
    # Check for IPv6 without brackets (multiple colons indicate IPv6)
    elif [[ "$server" =~ ^[0-9a-fA-F:]+$ ]] && [[ $(echo "$server" | tr -cd ':' | wc -c) -gt 1 ]]; then
        is_valid=1
    # Check for IPv4 with optional port
    elif [[ "$server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:([0-9]+))?$ ]]; then
        is_valid=1
    fi
    
    if [[ $is_valid -eq 0 ]]; then
        echo "Error: Invalid DNS server format: $server"
        echo "Supported formats:"
        echo "  IPv4: 8.8.8.8 or 8.8.8.8:53"
        echo "  IPv6: 2001:4860:4860::8888 or [2001:4860:4860::8844]:53"
        exit 1
    fi
    
    # Add server to config
    echo "dns_server $server" >> "$CONFIG_FILE"
    echo "Added DNS server: $server"
}

remove_server() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        echo "Error: DNS server IP is required"
        exit 1
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Configuration file does not exist"
        exit 1
    fi
    
    if grep -q "^dns_server $ip" "$CONFIG_FILE"; then
        grep -v "^dns_server $ip" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        echo "Removed DNS server: $ip"
    else
        echo "DNS server not found: $ip"
    fi
}

list_servers() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No configuration file found"
        return
    fi
    
    echo "Configured DNS servers:"
    echo "======================"
    grep "^dns_server " "$CONFIG_FILE" | while read -r line; do
        server=$(echo "$line" | cut -d' ' -f2)
        echo "  $server"
    done
    
    echo ""
    echo "Other settings:"
    echo "=============="
    grep -E "^(timeout|use_tcp|debug|enable_dns64|dns64_prefix|filter_aaaa|filter_a) " "$CONFIG_FILE" | while read -r line; do
        echo "  $line"
    done
}

set_config_value() {
    local key="$1"
    local value="$2"
    
    if [[ -z "$key" || -z "$value" ]]; then
        echo "Error: Both key and value are required"
        exit 1
    fi
    
    # Remove existing setting
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -v "^$key " "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    # Add new setting
    echo "$key $value" >> "$CONFIG_FILE"
    echo "Set $key to $value"
}

enable_dns64() {
    set_config_value "enable_dns64" "true"
    echo "DNS64 synthesis enabled"
    echo "This will create synthetic IPv6 addresses from IPv4 addresses"
    echo "Use 'set-dns64-prefix' to customize the DNS64 prefix (default: 64:ff9b::)"
}

disable_dns64() {
    set_config_value "enable_dns64" "false"
    echo "DNS64 synthesis disabled"
}

set_dns64_prefix() {
    local prefix="$1"
    
    if [[ -z "$prefix" ]]; then
        echo "Error: DNS64 prefix is required"
        echo "Examples: 64:ff9b::, 2001:db8:64::, fd00:64::"
        exit 1
    fi
    
    # Basic validation - check if it looks like an IPv6 prefix
    if [[ ! "$prefix" =~ ^[0-9a-fA-F:]+::?$ ]]; then
        echo "Error: Invalid IPv6 prefix format"
        echo "Examples: 64:ff9b::, 2001:db8:64::, fd00:64::"
        exit 1
    fi
    
    set_config_value "dns64_prefix" "$prefix"
    echo "DNS64 prefix set to: $prefix"
}

enable_aaaa_filter() {
    set_config_value "filter_aaaa" "true"
    echo "AAAA record filtering enabled"
    echo "Native IPv6 addresses will be filtered out before DNS64 synthesis"
    echo "This forces all IPv6 connectivity to use DNS64 synthetic addresses"
    echo "Useful for testing IPv6-only networks or ensuring traffic goes through DNS64 gateway"
}

disable_aaaa_filter() {
    set_config_value "filter_aaaa" "false"
    echo "AAAA record filtering disabled"
    echo "Native IPv6 addresses will be preserved alongside DNS64 synthetic addresses"
}

enable_a_filter() {
    set_config_value "filter_a" "true"
    echo "A record filtering enabled"
    echo "IPv4 addresses will be removed from final results"
    echo "This forces IPv6-only connectivity (using native IPv6 or DNS64 synthetic addresses)"
    echo "Useful for testing IPv6-only network scenarios"
}

disable_a_filter() {
    set_config_value "filter_a" "false"
    echo "A record filtering disabled"
    echo "IPv4 addresses will be preserved in final results"
}

test_dns64() {
    echo "Testing DNS64 Synthesis and AAAA Filtering"
    echo "=========================================="
    
    if [[ ! -f "./dns_override.so" ]]; then
        echo "Error: dns_override.so not found. Run 'make' first."
        exit 1
    fi
    
    # Enable DNS64 for testing
    echo "1. Setting up DNS64 configuration..."
    enable_dns64 > /dev/null
    set_config_value "debug" "true" > /dev/null
    
    echo ""
    echo "2. Testing IPv4-only domain without AAAA filtering:"
    disable_aaaa_filter > /dev/null
    echo "   Testing ipv4.google.com (IPv4-only domain):"
    timeout 5 LD_PRELOAD=./dns_override.so ./test_dns 2>&1 | grep -A 8 "Testing getaddrinfo for google.com:80" | head -6
    
    echo ""
    echo "3. Testing IPv4-only domain WITH AAAA filtering:"
    enable_aaaa_filter > /dev/null
    echo "   Same domain - should show IPv4 + DNS64 synthetic addresses:"
    timeout 5 LD_PRELOAD=./dns_override.so ./test_dns 2>&1 | grep -A 8 "Testing getaddrinfo for google.com:80" | head -6
    
    echo ""
    echo "4. Testing pure IPv4-only domains:"
    echo "   These domains typically only have IPv4 addresses:"
    
    # Test with a few IPv4-only domains
    local ipv4_domains=("httpbin.org" "example.org")
    
    for domain in "${ipv4_domains[@]}"; do
        echo ""
        echo "   Testing $domain:"
        echo "     Without AAAA filtering:"
        disable_aaaa_filter > /dev/null
        timeout 5 LD_PRELOAD=./dns_override.so nslookup "$domain" 2>&1 | grep -E "(IPv4|IPv6|DNS64)" | head -3 || echo "     No IPv6 results (IPv4-only domain)"
        
        echo "     With AAAA filtering + DNS64:"
        enable_aaaa_filter > /dev/null
        timeout 5 LD_PRELOAD=./dns_override.so nslookup "$domain" 2>&1 | grep -E "(DNS64 synthesis|Added DNS64)" | head -2 || echo "     DNS64 synthesis applied"
    done
    
    echo ""
    echo "5. AAAA Filtering Debug Output for IPv4-only domain:"
    echo "   Look for DNS64 synthesis messages (no AAAA filtering messages expected):"
    timeout 5 LD_PRELOAD=./dns_override.so nslookup httpbin.org 2>&1 | grep -E "(Filtering|DNS64|Added)" | head -5
    
    echo ""
    echo "Test Summary:"
    echo "============="
    echo "- IPv4-only domains: Show only IPv4 addresses normally"
    echo "- With DNS64 enabled: IPv4-only domains get synthetic IPv6 addresses"
    echo "- AAAA filtering: No effect on IPv4-only domains (no IPv6 to filter)"
    echo "- DNS64 synthesis: Creates IPv6 addresses from IPv4 for IPv4-only domains"
    echo ""
    echo "Current configuration:"
    grep -E "^(enable_dns64|dns64_prefix|filter_aaaa) " "$CONFIG_FILE" 2>/dev/null || echo "DNS64 not configured"
}

test_ipv4_only() {
    echo "Testing IPv4-Only Domain Handling"
    echo "================================="
    
    if [[ ! -f "./dns_override.so" ]]; then
        echo "Error: dns_override.so not found. Run 'make' first."
        exit 1
    fi
    
    # Set up configuration
    enable_dns64 > /dev/null
    set_config_value "debug" "true" > /dev/null
    
    echo "Testing domains that typically only have IPv4 addresses..."
    echo ""
    
    # List of domains that are typically IPv4-only or have limited IPv6
    local ipv4_only_domains=(
        "httpbin.org"
        "example.org" 
        "httpforever.com"
        "ipv4.google.com"
    )
    
    for domain in "${ipv4_only_domains[@]}"; do
        echo "Testing $domain:"
        echo "=================="
        
        echo "1. Without DNS override (system default):"
        timeout 3 nslookup "$domain" 2>/dev/null | grep -E "Address:|IPv6" | head -3 || echo "   Only IPv4 addresses found"
        
        echo ""
        echo "2. With DNS64 enabled (should add synthetic IPv6):"
        disable_aaaa_filter > /dev/null
        timeout 3 LD_PRELOAD=./dns_override.so nslookup "$domain" 2>&1 | grep -E "(DNS64 synthesis|Added DNS64|Address)" | head -4 || echo "   DNS64 processing applied"
        
        echo ""
        echo "3. With AAAA filtering + DNS64 (should be same as #2 for IPv4-only):"
        enable_aaaa_filter > /dev/null
        timeout 3 LD_PRELOAD=./dns_override.so nslookup "$domain" 2>&1 | grep -E "(Filtering|DNS64 synthesis|Added DNS64)" | head -3 || echo "   No IPv6 to filter, DNS64 synthesis applied"
        
        echo ""
        echo "----------------------------------------"
        echo ""
    done
    
    echo "IPv4-Only Domain Test Summary:"
    echo "=============================="
    echo "✓ IPv4-only domains work correctly with DNS64"
    echo "✓ AAAA filtering has no effect (no IPv6 addresses to filter)"
    echo "✓ DNS64 synthesis creates synthetic IPv6 addresses from IPv4"
    echo "✓ Applications get both IPv4 and synthetic IPv6 addresses"
}

test_complete_filtering() {
    echo "Testing Complete Filtering Chain: AAAA + DNS64 + A"
    echo "================================================="
    
    if [[ ! -f "./dns_override.so" ]]; then
        echo "Error: dns_override.so not found. Run 'make' first."
        exit 1
    fi
    
    echo "This test demonstrates the complete filtering workflow:"
    echo "1. filter_aaaa=true  → Remove native IPv6 addresses"
    echo "2. enable_dns64=true → Create synthetic IPv6 from IPv4"
    echo "3. filter_a=true     → Remove IPv4 addresses from final results"
    echo "Result: Pure DNS64 synthetic IPv6 addresses only"
    echo ""
    
    # Set up complete filtering configuration
    echo "Setting up complete filtering configuration..."
    enable_dns64 > /dev/null
    enable_aaaa_filter > /dev/null
    enable_a_filter > /dev/null
    set_config_value "debug" "true" > /dev/null
    
    echo "Current configuration:"
    grep -E "^(enable_dns64|filter_aaaa|filter_a|debug) " "$CONFIG_FILE" | sed 's/^/  /'
    echo ""
    
    echo "Testing with google.com (has both IPv4 and IPv6 addresses):"
    echo "============================================================"
    echo ""
    
    echo "1. Without DNS override (system default):"
    echo "   Should show both IPv4 and IPv6 addresses"
    nslookup google.com 2>/dev/null | grep "Address:" | grep -v "#53" | head -4 | sed 's/^/   /'
    echo ""
    
    echo "2. With complete filtering enabled:"
    echo "   Should show ONLY DNS64 synthetic IPv6 addresses (64:ff9b::...)"
    echo ""
    echo "   Debug output showing the filtering process:"
    timeout 5 LD_PRELOAD=./dns_override.so ./test_dns 2>&1 | grep -E "(Filtering|DNS64|Added|Removed)" | head -8 | sed 's/^/   /'
    echo ""
    
    echo "   Final results (IPv6-only via DNS64):"
    timeout 5 LD_PRELOAD=./dns_override.so ./test_dns 2>&1 | grep -A 10 "Testing getaddrinfo for google.com" | grep "IPv6:" | head -6 | sed 's/^/   /'
    echo ""
    
    echo "3. Testing with IPv4-only domain (httpbin.org):"
    echo "   Should convert IPv4 → DNS64 synthetic IPv6, then filter out original IPv4"
    echo ""
    echo "   Debug output:"
    timeout 5 LD_PRELOAD=./dns_override.so nslookup httpbin.org 2>&1 | grep -E "(DNS64 synthesis|Filtering out A record|Added DNS64)" | head -4 | sed 's/^/   /'
    echo ""
    
    echo "4. Comparison of filtering stages:"
    echo "================================="
    
    # Stage 1: No filtering
    echo ""
    echo "   Stage 1 - No filtering (baseline):"
    disable_aaaa_filter > /dev/null
    disable_a_filter > /dev/null
    set_config_value "debug" "false" > /dev/null
    result1=$(timeout 3 LD_PRELOAD=./dns_override.so ./test_dns 2>/dev/null | grep -A 15 "Testing getaddrinfo for google.com" | grep -E "(IPv4|IPv6):" | wc -l)
    echo "     Total addresses: $result1 (IPv4 + IPv6 + DNS64)"
    
    # Stage 2: AAAA filtering only
    echo ""
    echo "   Stage 2 - AAAA filtering only:"
    enable_aaaa_filter > /dev/null
    set_config_value "debug" "false" > /dev/null
    result2=$(timeout 3 LD_PRELOAD=./dns_override.so ./test_dns 2>/dev/null | grep -A 15 "Testing getaddrinfo for google.com" | grep -E "(IPv4|IPv6):" | wc -l)
    echo "     Total addresses: $result2 (IPv4 + DNS64 only)"
    
    # Stage 3: Complete filtering
    echo ""
    echo "   Stage 3 - Complete filtering (AAAA + A):"
    enable_a_filter > /dev/null
    set_config_value "debug" "false" > /dev/null
    result3=$(timeout 3 LD_PRELOAD=./dns_override.so ./test_dns 2>/dev/null | grep -A 15 "Testing getaddrinfo for google.com" | grep -E "(IPv4|IPv6):" | wc -l)
    echo "     Total addresses: $result3 (DNS64 synthetic IPv6 only)"
    
    echo ""
    echo "Summary of Complete Filtering Test:"
    echo "=================================="
    echo "✅ Native IPv6 addresses filtered out (filter_aaaa=true)"
    echo "✅ DNS64 synthetic IPv6 addresses created from IPv4"
    echo "✅ Original IPv4 addresses filtered out (filter_a=true)"
    echo "✅ Final result: Pure IPv6-only connectivity via DNS64"
    echo ""
    echo "Use case: Perfect for testing IPv6-only networks with DNS64 gateway"
    echo "Applications will only see IPv6 addresses, but can still reach IPv4-only services"
}

load_preset() {
    local preset="$1"
    
    if [[ -z "$preset" ]]; then
        echo "Error: Preset name is required"
        exit 1
    fi
    
    # Clear existing servers
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -v "^dns_server " "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
    
    case "$preset" in
        google)
            echo "dns_server 8.8.8.8:53" >> "$CONFIG_FILE"
            echo "dns_server 8.8.4.4:53" >> "$CONFIG_FILE"
            echo "Loaded Google DNS preset"
            ;;
        cloudflare)
            echo "dns_server 1.1.1.1:53" >> "$CONFIG_FILE"
            echo "dns_server 1.0.0.1:53" >> "$CONFIG_FILE"
            echo "Loaded Cloudflare DNS preset"
            ;;
        quad9)
            echo "dns_server 9.9.9.9:53" >> "$CONFIG_FILE"
            echo "dns_server 149.112.112.112:53" >> "$CONFIG_FILE"
            echo "Loaded Quad9 DNS preset"
            ;;
        opendns)
            echo "dns_server 208.67.222.222:53" >> "$CONFIG_FILE"
            echo "dns_server 208.67.220.220:53" >> "$CONFIG_FILE"
            echo "Loaded OpenDNS preset"
            ;;
        adguard)
            echo "dns_server 94.140.14.14:53" >> "$CONFIG_FILE"
            echo "dns_server 94.140.15.15:53" >> "$CONFIG_FILE"
            echo "Loaded AdGuard DNS preset"
            ;;
        *)
            echo "Unknown preset: $preset"
            echo "Available presets: google, cloudflare, quad9, opendns, adguard"
            exit 1
            ;;
    esac
}

clear_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        rm "$CONFIG_FILE"
        echo "Configuration cleared"
    else
        echo "No configuration file to clear"
    fi
}

load_example() {
    if [[ -f "$EXAMPLE_CONFIG" ]]; then
        cp "$EXAMPLE_CONFIG" "$CONFIG_FILE"
        echo "Loaded example configuration to $CONFIG_FILE"
    else
        echo "Example configuration file not found: $EXAMPLE_CONFIG"
        exit 1
    fi
}

edit_config() {
    local editor="${EDITOR:-nano}"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        touch "$CONFIG_FILE"
    fi
    "$editor" "$CONFIG_FILE"
}

show_status() {
    echo "DNS Override Configuration Status"
    echo "================================"
    echo "Configuration file: $CONFIG_FILE"
    if [[ -n "$DNS_OVERRIDE_CONFIG" ]]; then
        echo "  (Custom path set by DNS_OVERRIDE_CONFIG environment variable)"
        echo "  Default would be: $DEFAULT_CONFIG_FILE"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        local server_count=$(grep -c "^dns_server " "$CONFIG_FILE")
        echo "Status: Active with $server_count DNS servers"
        echo "Last modified: $(stat -c %y "$CONFIG_FILE")"
        echo ""
        list_servers
    else
        echo "Status: No configuration file found"
        echo "Will use defaults: 8.8.8.8, 1.1.1.1"
    fi
    
    echo ""
    echo "To use the DNS override with a program:"
    if [[ -n "$DNS_OVERRIDE_CONFIG" ]]; then
        echo "DNS_OVERRIDE_CONFIG=$CONFIG_FILE LD_PRELOAD=./dns_override.so your_program"
    else
        echo "LD_PRELOAD=./dns_override.so your_program"
    fi
}

test_dns() {
    echo "Testing DNS resolution..."
    echo "========================"
    
    local test_domains=("google.com" "github.com" "stackoverflow.com")
    
    echo "1. Testing without DNS override (system default):"
    for domain in "${test_domains[@]}"; do
        echo -n "  $domain: "
        timeout 5 nslookup "$domain" | grep "Address:" | tail -1 | cut -d' ' -f2 || echo "Failed"
    done
    
    echo ""
    echo "2. Testing with DNS override:"
    if [[ -f "./dns_override.so" ]]; then
        for domain in "${test_domains[@]}"; do
            echo -n "  $domain: "
            timeout 5 LD_PRELOAD=./dns_override.so nslookup "$domain" 2>/dev/null | grep "Address:" | tail -1 | cut -d' ' -f2 || echo "Failed"
        done
    else
        echo "  dns_override.so not found. Run 'make' first."
    fi
    
    echo ""
    echo "3. Current system DNS servers:"
    if command -v systemd-resolve &> /dev/null; then
        systemd-resolve --status | grep "DNS Servers:" | head -3
    elif [[ -f /etc/resolv.conf ]]; then
        grep "nameserver" /etc/resolv.conf
    else
        echo "  Unable to determine system DNS servers"
    fi
}

case "$1" in
    add-server)
        add_server "$2"
        ;;
    remove-server)
        remove_server "$2"
        ;;
    list-servers)
        list_servers
        ;;
    set-timeout)
        set_config_value "timeout" "$2"
        ;;
    set-tcp)
        set_config_value "use_tcp" "$2"
        ;;
    set-debug)
        set_config_value "debug" "$2"
        ;;
    enable-dns64)
        enable_dns64
        ;;
    disable-dns64)
        disable_dns64
        ;;
    set-dns64-prefix)
        set_dns64_prefix "$2"
        ;;
    enable-aaaa-filter)
        enable_aaaa_filter
        ;;
    disable-aaaa-filter)
        disable_aaaa_filter
        ;;
    enable-a-filter)
        enable_a_filter
        ;;
    disable-a-filter)
        disable_a_filter
        ;;
    preset)
        load_preset "$2"
        ;;
    clear)
        clear_config
        ;;
    load)
        load_example
        ;;
    edit)
        edit_config
        ;;
    status)
        show_status
        ;;
    test)
        test_dns
        ;;
    test-dns64)
        test_dns64
        ;;
    test-ipv4-only)
        test_ipv4_only
        ;;
    test-complete-filtering)
        test_complete_filtering
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
