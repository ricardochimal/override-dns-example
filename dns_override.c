#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <resolv.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/time.h>

// Configuration file path
#define DEFAULT_CONFIG_FILE "/tmp/dns_override.conf"
#define CONFIG_ENV_VAR "DNS_OVERRIDE_CONFIG"
#define MAX_DNS_SERVERS 8
#define DEFAULT_DNS_PORT 53

// Get configuration file path from environment or use default
static const char* get_config_file_path() {
    const char* env_path = getenv(CONFIG_ENV_VAR);
    return env_path ? env_path : DEFAULT_CONFIG_FILE;
}

// Structure to hold DNS server configuration
struct dns_config {
    char dns_servers[MAX_DNS_SERVERS][46]; // Support both IPv4 and IPv6
    int dns_ports[MAX_DNS_SERVERS];
    int server_count;
    int timeout_ms;
    int use_tcp;
    int debug;
    int enable_dns64;
    char dns64_prefix[46]; // DNS64 prefix (e.g., "64:ff9b::/96")
    int filter_aaaa; // Filter out AAAA records before DNS64 synthesis
};

static struct dns_config config = {0};
static int config_loaded = 0;

// Function pointers to original functions
static struct hostent *(*original_gethostbyname)(const char *name) = NULL;
static int (*original_getaddrinfo)(const char *node, const char *service,
                                 const struct addrinfo *hints,
                                 struct addrinfo **res) = NULL;

// Load DNS server configuration from file
static void load_dns_config() {
    if (config_loaded) return;
    
    // Set defaults
    config.server_count = 0;
    config.timeout_ms = 5000;
    config.use_tcp = 0;
    config.debug = 0;
    config.enable_dns64 = 0;
    config.filter_aaaa = 0;
    strncpy(config.dns64_prefix, "64:ff9b::", sizeof(config.dns64_prefix) - 1);
    config.dns64_prefix[sizeof(config.dns64_prefix) - 1] = '\0';
    
    const char* config_file = get_config_file_path();
    FILE *file = fopen(config_file, "r");
    if (!file) {
        // Use default DNS servers if no config file
        strncpy(config.dns_servers[0], "8.8.8.8", sizeof(config.dns_servers[0]) - 1);
        config.dns_ports[0] = DEFAULT_DNS_PORT;
        strncpy(config.dns_servers[1], "1.1.1.1", sizeof(config.dns_servers[1]) - 1);
        config.dns_ports[1] = DEFAULT_DNS_PORT;
        config.server_count = 2;
        fprintf(stderr, "[DNS Override] Config file not found: %s\n", config_file);
        fprintf(stderr, "[DNS Override] Using default DNS servers: 8.8.8.8, 1.1.1.1\n");
        config_loaded = 1;
        return;
    }
    
    if (config.debug) {
        fprintf(stderr, "[DNS Override] Loading configuration from: %s\n", config_file);
    }
    
    char line[512];
    while (fgets(line, sizeof(line), file)) {
        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') continue;
        
        // Remove trailing newline
        line[strcspn(line, "\r\n")] = 0;
        
        char key[256], value[256];
        if (sscanf(line, "%255s %255s", key, value) == 2) {
            if (strcmp(key, "dns_server") == 0 && config.server_count < MAX_DNS_SERVERS) {
                char *port_str = strchr(value, ':');
                if (port_str) {
                    *port_str = '\0';
                    port_str++;
                    config.dns_ports[config.server_count] = atoi(port_str);
                } else {
                    config.dns_ports[config.server_count] = DEFAULT_DNS_PORT;
                }
                strncpy(config.dns_servers[config.server_count], value, 
                       sizeof(config.dns_servers[config.server_count]) - 1);
                config.dns_servers[config.server_count][sizeof(config.dns_servers[config.server_count]) - 1] = '\0';
                fprintf(stderr, "[DNS Override] Added DNS server: %s:%d\n", 
                       config.dns_servers[config.server_count], config.dns_ports[config.server_count]);
                config.server_count++;
            } else if (strcmp(key, "timeout") == 0) {
                config.timeout_ms = atoi(value);
            } else if (strcmp(key, "use_tcp") == 0) {
                config.use_tcp = (strcmp(value, "true") == 0 || strcmp(value, "1") == 0);
            } else if (strcmp(key, "debug") == 0) {
                config.debug = (strcmp(value, "true") == 0 || strcmp(value, "1") == 0);
            } else if (strcmp(key, "enable_dns64") == 0) {
                config.enable_dns64 = (strcmp(value, "true") == 0 || strcmp(value, "1") == 0);
                if (config.enable_dns64) {
                    fprintf(stderr, "[DNS Override] DNS64 synthesis enabled\n");
                }
            } else if (strcmp(key, "dns64_prefix") == 0) {
                strncpy(config.dns64_prefix, value, sizeof(config.dns64_prefix) - 1);
                config.dns64_prefix[sizeof(config.dns64_prefix) - 1] = '\0';
                fprintf(stderr, "[DNS Override] DNS64 prefix: %s\n", config.dns64_prefix);
            } else if (strcmp(key, "filter_aaaa") == 0) {
                config.filter_aaaa = (strcmp(value, "true") == 0 || strcmp(value, "1") == 0);
                if (config.filter_aaaa) {
                    fprintf(stderr, "[DNS Override] AAAA record filtering enabled - native IPv6 addresses will be removed\n");
                }
            }
        }
    }
    
    fclose(file);
    
    // If no servers were configured, use defaults
    if (config.server_count == 0) {
        strncpy(config.dns_servers[0], "8.8.8.8", sizeof(config.dns_servers[0]) - 1);
        config.dns_ports[0] = DEFAULT_DNS_PORT;
        strncpy(config.dns_servers[1], "1.1.1.1", sizeof(config.dns_servers[1]) - 1);
        config.dns_ports[1] = DEFAULT_DNS_PORT;
        config.server_count = 2;
        fprintf(stderr, "[DNS Override] No servers configured, using defaults\n");
    }
    
    config_loaded = 1;
}

// Initialize original function pointers
static void init_original_functions() {
    if (!original_gethostbyname) {
        original_gethostbyname = dlsym(RTLD_NEXT, "gethostbyname");
    }
    if (!original_getaddrinfo) {
        original_getaddrinfo = dlsym(RTLD_NEXT, "getaddrinfo");
    }
}

// DNS64 synthesis: Convert IPv4 address to IPv6 using DNS64 prefix
static int synthesize_dns64_address(const char *ipv4_str, char *ipv6_str, size_t ipv6_len) {
    struct in_addr ipv4_addr;
    if (inet_pton(AF_INET, ipv4_str, &ipv4_addr) != 1) {
        return 0; // Invalid IPv4 address
    }
    
    // Parse DNS64 prefix (default: 64:ff9b::)
    char prefix[46];
    strncpy(prefix, config.dns64_prefix, sizeof(prefix) - 1);
    prefix[sizeof(prefix) - 1] = '\0';
    
    // Remove trailing :: if present
    char *double_colon = strstr(prefix, "::");
    if (double_colon) {
        *double_colon = '\0';
    }
    
    // Convert IPv4 to hex representation
    uint32_t ipv4_net = ntohl(ipv4_addr.s_addr);
    uint16_t high = (ipv4_net >> 16) & 0xFFFF;
    uint16_t low = ipv4_net & 0xFFFF;
    
    // Create DNS64 address: prefix + IPv4 embedded
    // For 64:ff9b::/96 prefix, format is: 64:ff9b::XXXX:YYYY
    // where XXXX:YYYY is the IPv4 address in hex
    snprintf(ipv6_str, ipv6_len, "%s::%x:%x", prefix, high, low);
    
    if (config.debug) {
        fprintf(stderr, "[DNS Override] DNS64 synthesis: %s -> %s\n", ipv4_str, ipv6_str);
    }
    
    return 1; // Success
}

// Create synthetic IPv6 addresses from IPv4 results
static int add_dns64_addresses(struct addrinfo **result, struct addrinfo *ipv4_results) {
    if (!config.enable_dns64 || !ipv4_results) {
        return 0;
    }
    
    struct addrinfo *current = ipv4_results;
    struct addrinfo *last_result = *result;
    
    // Find the end of the current result chain
    if (last_result) {
        while (last_result->ai_next) {
            last_result = last_result->ai_next;
        }
    }
    
    int added_count = 0;
    
    while (current) {
        if (current->ai_family == AF_INET) {
            struct sockaddr_in *ipv4_addr = (struct sockaddr_in *)current->ai_addr;
            char ipv4_str[INET_ADDRSTRLEN];
            char ipv6_str[INET6_ADDRSTRLEN];
            
            // Convert IPv4 to string
            if (inet_ntop(AF_INET, &ipv4_addr->sin_addr, ipv4_str, sizeof(ipv4_str))) {
                // Synthesize DNS64 address
                if (synthesize_dns64_address(ipv4_str, ipv6_str, sizeof(ipv6_str))) {
                    // Create new IPv6 addrinfo structure
                    struct addrinfo *new_ai = malloc(sizeof(struct addrinfo));
                    struct sockaddr_in6 *ipv6_sockaddr = malloc(sizeof(struct sockaddr_in6));
                    
                    if (new_ai && ipv6_sockaddr) {
                        memset(new_ai, 0, sizeof(struct addrinfo));
                        memset(ipv6_sockaddr, 0, sizeof(struct sockaddr_in6));
                        
                        // Set up IPv6 address structure
                        ipv6_sockaddr->sin6_family = AF_INET6;
                        ipv6_sockaddr->sin6_port = ipv4_addr->sin_port;
                        
                        if (inet_pton(AF_INET6, ipv6_str, &ipv6_sockaddr->sin6_addr) == 1) {
                            // Set up addrinfo structure
                            new_ai->ai_family = AF_INET6;
                            new_ai->ai_socktype = current->ai_socktype;
                            new_ai->ai_protocol = current->ai_protocol;
                            new_ai->ai_addrlen = sizeof(struct sockaddr_in6);
                            new_ai->ai_addr = (struct sockaddr *)ipv6_sockaddr;
                            new_ai->ai_next = NULL;
                            
                            // Add to result chain
                            if (last_result) {
                                last_result->ai_next = new_ai;
                            } else {
                                *result = new_ai;
                            }
                            last_result = new_ai;
                            added_count++;
                            
                            if (config.debug) {
                                fprintf(stderr, "[DNS Override] Added DNS64 address: %s\n", ipv6_str);
                            }
                        } else {
                            free(new_ai);
                            free(ipv6_sockaddr);
                        }
                    } else {
                        free(new_ai);
                        free(ipv6_sockaddr);
                    }
                }
            }
        }
        current = current->ai_next;
    }
    
    return added_count;
}

// Filter out AAAA (IPv6) records from DNS results
static int filter_aaaa_records(struct addrinfo **result) {
    if (!config.filter_aaaa || !*result) {
        return 0;
    }
    
    struct addrinfo *current = *result;
    struct addrinfo *prev = NULL;
    int removed_count = 0;
    
    while (current) {
        if (current->ai_family == AF_INET6) {
            // This is an IPv6 address, remove it
            struct addrinfo *to_remove = current;
            
            if (config.debug) {
                char ipv6_str[INET6_ADDRSTRLEN];
                struct sockaddr_in6 *ipv6_addr = (struct sockaddr_in6 *)current->ai_addr;
                if (inet_ntop(AF_INET6, &ipv6_addr->sin6_addr, ipv6_str, sizeof(ipv6_str))) {
                    fprintf(stderr, "[DNS Override] Filtering out AAAA record: %s\n", ipv6_str);
                }
            }
            
            // Update links
            if (prev) {
                prev->ai_next = current->ai_next;
            } else {
                *result = current->ai_next;
            }
            
            current = current->ai_next;
            
            // Free the removed record
            free(to_remove->ai_addr);
            free(to_remove);
            removed_count++;
        } else {
            // Keep this record (IPv4)
            prev = current;
            current = current->ai_next;
        }
    }
    
    if (removed_count > 0 && config.debug) {
        fprintf(stderr, "[DNS Override] Filtered out %d AAAA records\n", removed_count);
    }
    
    return removed_count;
}

// Perform DNS query using custom DNS server
static int query_custom_dns(const char *hostname, int query_type, void *result_buffer, size_t buffer_size) {
    load_dns_config();
    
    if (config.debug) {
        fprintf(stderr, "[DNS Override] Querying custom DNS for %s (type %d)\n", hostname, query_type);
    }
    
    // Try each configured DNS server
    for (int server_idx = 0; server_idx < config.server_count; server_idx++) {
        int sockfd;
        struct sockaddr_in server_addr;
        
        // Create socket
        sockfd = socket(AF_INET, config.use_tcp ? SOCK_STREAM : SOCK_DGRAM, 0);
        if (sockfd < 0) {
            continue;
        }
        
        // Set socket timeout
        struct timeval timeout;
        timeout.tv_sec = config.timeout_ms / 1000;
        timeout.tv_usec = (config.timeout_ms % 1000) * 1000;
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        
        // Setup server address
        memset(&server_addr, 0, sizeof(server_addr));
        server_addr.sin_family = AF_INET;
        server_addr.sin_port = htons(config.dns_ports[server_idx]);
        
        if (inet_pton(AF_INET, config.dns_servers[server_idx], &server_addr.sin_addr) != 1) {
            close(sockfd);
            continue;
        }
        
        // Connect to DNS server
        if (connect(sockfd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
            close(sockfd);
            continue;
        }
        
        // For simplicity, we'll use the system's resolver but modify the nameserver
        // This is a simplified approach - a full implementation would build DNS packets
        close(sockfd);
        
        if (config.debug) {
            fprintf(stderr, "[DNS Override] Using DNS server %s:%d\n", 
                   config.dns_servers[server_idx], config.dns_ports[server_idx]);
        }
        
        // Modify resolv.conf temporarily or use res_ninit with custom configuration
        // For now, we'll use a different approach by calling the original function
        // but with modified resolver state
        return 1; // Success indicator
    }
    
    return 0; // Failed to query any server
}

// Override gethostbyname to use custom DNS servers
struct hostent *gethostbyname(const char *name) {
    init_original_functions();
    load_dns_config();
    
    if (config.debug) {
        fprintf(stderr, "[DNS Override] gethostbyname called for: %s\n", name);
    }
    
    // Save original resolver state
    struct __res_state original_state;
    memcpy(&original_state, &_res, sizeof(_res));
    
    // Modify resolver to use our DNS servers
    res_init();
    _res.nscount = 0;
    
    for (int i = 0; i < config.server_count && i < MAXNS; i++) {
        struct sockaddr_in *ns = (struct sockaddr_in*)&_res.nsaddr_list[i];
        memset(ns, 0, sizeof(*ns));
        ns->sin_family = AF_INET;
        ns->sin_port = htons(config.dns_ports[i]);
        
        if (inet_pton(AF_INET, config.dns_servers[i], &ns->sin_addr) == 1) {
            _res.nscount++;
            if (config.debug) {
                fprintf(stderr, "[DNS Override] Using nameserver: %s:%d\n", 
                       config.dns_servers[i], config.dns_ports[i]);
            }
        }
    }
    
    // Set timeout
    _res.retrans = config.timeout_ms / 1000;
    _res.retry = 2;
    
    // Call original function with modified resolver
    struct hostent *result = original_gethostbyname(name);
    
    // Restore original resolver state
    memcpy(&_res, &original_state, sizeof(_res));
    
    if (config.debug) {
        if (result) {
            fprintf(stderr, "[DNS Override] gethostbyname succeeded for %s\n", name);
        } else {
            fprintf(stderr, "[DNS Override] gethostbyname failed for %s\n", name);
        }
    }
    
    return result;
}

// Override getaddrinfo to use custom DNS servers
int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res) {
    init_original_functions();
    load_dns_config();
    
    if (config.debug && node) {
        fprintf(stderr, "[DNS Override] getaddrinfo called for: %s\n", node);
    }
    
    // Save original resolver state
    struct __res_state original_state;
    memcpy(&original_state, &_res, sizeof(_res));
    
    // Modify resolver to use our DNS servers
    res_init();
    _res.nscount = 0;
    
    for (int i = 0; i < config.server_count && i < MAXNS; i++) {
        struct sockaddr_in *ns = (struct sockaddr_in*)&_res.nsaddr_list[i];
        memset(ns, 0, sizeof(*ns));
        ns->sin_family = AF_INET;
        ns->sin_port = htons(config.dns_ports[i]);
        
        if (inet_pton(AF_INET, config.dns_servers[i], &ns->sin_addr) == 1) {
            _res.nscount++;
            if (config.debug && node) {
                fprintf(stderr, "[DNS Override] Using nameserver: %s:%d for %s\n", 
                       config.dns_servers[i], config.dns_ports[i], node);
            }
        }
    }
    
    // Set timeout
    _res.retrans = config.timeout_ms / 1000;
    _res.retry = 2;
    
    // Call original function with modified resolver
    int result = original_getaddrinfo(node, service, hints, res);
    
    // If we got results, apply filtering and DNS64 processing
    if (result == 0 && node && *res) {
        // First, filter out AAAA records if requested
        if (config.filter_aaaa) {
            int filtered = filter_aaaa_records(res);
            if (filtered > 0 && config.debug) {
                fprintf(stderr, "[DNS Override] Removed %d native IPv6 addresses for %s\n", filtered, node);
            }
        }
        
        // Then, if DNS64 is enabled, add synthetic IPv6 addresses
        if (config.enable_dns64 && *res) {
            // Create a copy of the current results to process for DNS64
            struct addrinfo *ipv4_results = *res;
            
            // Add DNS64 synthetic addresses
            int added = add_dns64_addresses(res, ipv4_results);
            
            if (added > 0 && config.debug) {
                fprintf(stderr, "[DNS Override] Added %d DNS64 synthetic addresses for %s\n", added, node);
            }
        }
    }
    
    // Restore original resolver state
    memcpy(&_res, &original_state, sizeof(_res));
    
    if (config.debug && node) {
        if (result == 0) {
            fprintf(stderr, "[DNS Override] getaddrinfo succeeded for %s\n", node);
        } else {
            fprintf(stderr, "[DNS Override] getaddrinfo failed for %s: %s\n", node, gai_strerror(result));
        }
    }
    
    return result;
}

// Constructor to initialize when library is loaded
__attribute__((constructor))
static void dns_override_init() {
    const char* config_file = get_config_file_path();
    fprintf(stderr, "[DNS Override] Upstream DNS resolver override loaded. Config: %s\n", config_file);
    if (getenv(CONFIG_ENV_VAR)) {
        fprintf(stderr, "[DNS Override] Using custom config path from %s environment variable\n", CONFIG_ENV_VAR);
    }
    load_dns_config();
}

// Destructor to cleanup when library is unloaded
__attribute__((destructor))
static void dns_override_cleanup() {
    fprintf(stderr, "[DNS Override] Upstream DNS resolver override unloaded.\n");
}