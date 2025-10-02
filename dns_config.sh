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
    echo "  preset <name>           Load a DNS provider preset"
    echo "  clear                   Clear all configuration"
    echo "  load                    Load example configuration"
    echo "  edit                    Edit configuration file"
    echo "  status                  Show configuration status"
    echo "  test                    Test DNS resolution"
    echo "  test-dns64              Test DNS64 synthesis"
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
    echo "  $0 test-dns64"
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
        echo "Error: DNS server IP is required"
        exit 1
    fi
    
    # Validate IP address format (basic validation)
    local ip=$(echo "$server" | cut -d':' -f1)
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        echo "Error: Invalid IP address format"
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
    grep -E "^(timeout|use_tcp|debug|enable_dns64|dns64_prefix|filter_aaaa) " "$CONFIG_FILE" | while read -r line; do
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
    echo "2. Testing without AAAA filtering (native + synthetic IPv6):"
    disable_aaaa_filter > /dev/null
    echo "   Domain with both IPv4 and IPv6 addresses:"
    timeout 5 LD_PRELOAD=./dns_override.so ./test_dns 2>&1 | grep -A 10 "Testing getaddrinfo for google.com:80" | head -8
    
    echo ""
    echo "3. Testing WITH AAAA filtering (synthetic IPv6 only):"
    enable_aaaa_filter > /dev/null
    echo "   Same domain with native IPv6 addresses filtered out:"
    timeout 5 LD_PRELOAD=./dns_override.so ./test_dns 2>&1 | grep -A 10 "Testing getaddrinfo for google.com:80" | head -8
    
    echo ""
    echo "4. AAAA Filtering Debug Output:"
    echo "   Look for 'Filtering out AAAA record' messages:"
    timeout 5 LD_PRELOAD=./dns_override.so nslookup google.com 2>&1 | grep -E "(Filtering|AAAA)" | head -3
    
    echo ""
    echo "Test Summary:"
    echo "============="
    echo "- Without AAAA filtering: Shows both native IPv6 and DNS64 synthetic addresses"
    echo "- With AAAA filtering: Shows only IPv4 and DNS64 synthetic addresses"
    echo "- AAAA filtering forces all IPv6 traffic through DNS64 gateway"
    echo ""
    echo "Current configuration:"
    grep -E "^(enable_dns64|dns64_prefix|filter_aaaa) " "$CONFIG_FILE" 2>/dev/null || echo "DNS64 not configured"
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
    *)
        show_usage
        exit 1
        ;;
esac
