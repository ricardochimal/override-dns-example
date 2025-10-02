#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <time.h>

void print_system_dns_info() {
    printf("\n=== System DNS Information ===\n");
    
    // Try to read /etc/resolv.conf
    FILE *resolv = fopen("/etc/resolv.conf", "r");
    if (resolv) {
        printf("System DNS servers from /etc/resolv.conf:\n");
        char line[256];
        while (fgets(line, sizeof(line), resolv)) {
            if (strncmp(line, "nameserver", 10) == 0) {
                printf("  %s", line);
            }
        }
        fclose(resolv);
    } else {
        printf("Could not read /etc/resolv.conf\n");
    }
    
    // Try to get systemd-resolved info
    printf("\nNote: Use 'systemd-resolve --status' for detailed DNS info on systemd systems\n");
}

void test_gethostbyname(const char *hostname) {
    printf("\n=== Testing gethostbyname for %s ===\n", hostname);
    
    clock_t start = clock();
    struct hostent *host_entry = gethostbyname(hostname);
    clock_t end = clock();
    
    double time_taken = ((double)(end - start)) / CLOCKS_PER_SEC * 1000;
    
    if (host_entry == NULL) {
        printf("gethostbyname failed for %s (%.2f ms)\n", hostname, time_taken);
        switch (h_errno) {
            case HOST_NOT_FOUND:
                printf("  Error: Host not found\n");
                break;
            case NO_ADDRESS:
                printf("  Error: No address associated with hostname\n");
                break;
            case NO_RECOVERY:
                printf("  Error: Non-recoverable name server error\n");
                break;
            case TRY_AGAIN:
                printf("  Error: Temporary failure in name resolution\n");
                break;
            default:
                printf("  Error: Unknown error\n");
                break;
        }
        return;
    }
    
    printf("Hostname: %s (%.2f ms)\n", host_entry->h_name, time_taken);
    printf("Address type: %s\n", (host_entry->h_addrtype == AF_INET) ? "IPv4" : "IPv6");
    printf("Address length: %d\n", host_entry->h_length);
    
    printf("IP addresses:\n");
    for (int i = 0; host_entry->h_addr_list[i] != NULL; i++) {
        struct in_addr addr;
        memcpy(&addr, host_entry->h_addr_list[i], sizeof(struct in_addr));
        printf("  %s\n", inet_ntoa(addr));
    }
    
    // Show aliases if any
    if (host_entry->h_aliases && host_entry->h_aliases[0]) {
        printf("Aliases:\n");
        for (int i = 0; host_entry->h_aliases[i] != NULL; i++) {
            printf("  %s\n", host_entry->h_aliases[i]);
        }
    }
}

void test_getaddrinfo(const char *hostname, const char *port) {
    printf("\n=== Testing getaddrinfo for %s:%s ===\n", hostname, port ? port : "N/A");
    
    struct addrinfo hints, *result, *rp;
    
    memset(&hints, 0, sizeof(struct addrinfo));
    hints.ai_family = AF_UNSPEC;    // Allow IPv4 or IPv6
    hints.ai_socktype = SOCK_STREAM; // TCP socket
    
    clock_t start = clock();
    int status = getaddrinfo(hostname, port, &hints, &result);
    clock_t end = clock();
    
    double time_taken = ((double)(end - start)) / CLOCKS_PER_SEC * 1000;
    
    if (status != 0) {
        printf("getaddrinfo failed (%.2f ms): %s\n", time_taken, gai_strerror(status));
        return;
    }
    
    printf("Results (%.2f ms):\n", time_taken);
    int count = 0;
    for (rp = result; rp != NULL; rp = rp->ai_next) {
        void *addr;
        char *ipver;
        char ipstr[INET6_ADDRSTRLEN];
        int port_num = 0;
        
        if (rp->ai_family == AF_INET) { // IPv4
            struct sockaddr_in *ipv4 = (struct sockaddr_in *)rp->ai_addr;
            addr = &(ipv4->sin_addr);
            port_num = ntohs(ipv4->sin_port);
            ipver = "IPv4";
        } else { // IPv6
            struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)rp->ai_addr;
            addr = &(ipv6->sin6_addr);
            port_num = ntohs(ipv6->sin6_port);
            ipver = "IPv6";
        }
        
        inet_ntop(rp->ai_family, addr, ipstr, INET6_ADDRSTRLEN);
        if (port_num > 0) {
            printf("  %s: %s:%d\n", ipver, ipstr, port_num);
        } else {
            printf("  %s: %s\n", ipver, ipstr);
        }
        count++;
    }
    
    printf("Total addresses found: %d\n", count);
    freeaddrinfo(result);
}

void test_dns_performance(const char *hostname, int iterations) {
    printf("\n=== DNS Performance Test for %s (%d iterations) ===\n", hostname, iterations);
    
    double total_time = 0;
    int successful_queries = 0;
    
    for (int i = 0; i < iterations; i++) {
        clock_t start = clock();
        struct hostent *host_entry = gethostbyname(hostname);
        clock_t end = clock();
        
        double time_taken = ((double)(end - start)) / CLOCKS_PER_SEC * 1000;
        total_time += time_taken;
        
        if (host_entry != NULL) {
            successful_queries++;
        }
        
        if (i < 3) { // Show details for first 3 queries
            printf("Query %d: %.2f ms (%s)\n", i + 1, time_taken, 
                   host_entry ? "Success" : "Failed");
        }
        
        // Small delay between queries
        usleep(100000); // 100ms
    }
    
    printf("Performance Summary:\n");
    printf("  Total queries: %d\n", iterations);
    printf("  Successful: %d (%.1f%%)\n", successful_queries, 
           (successful_queries * 100.0) / iterations);
    printf("  Average time: %.2f ms\n", total_time / iterations);
    printf("  Total time: %.2f ms\n", total_time);
}

void test_multiple_domains() {
    printf("\n=== Testing Multiple Domains ===\n");
    
    const char *test_domains[] = {
        "google.com",
        "github.com",
        "stackoverflow.com",
        "reddit.com",
        "wikipedia.org",
        "cloudflare.com",
        NULL
    };
    
    for (int i = 0; test_domains[i] != NULL; i++) {
        printf("\n%d. Testing %s:\n", i + 1, test_domains[i]);
        
        clock_t start = clock();
        struct hostent *host_entry = gethostbyname(test_domains[i]);
        clock_t end = clock();
        
        double time_taken = ((double)(end - start)) / CLOCKS_PER_SEC * 1000;
        
        if (host_entry) {
            struct in_addr addr;
            memcpy(&addr, host_entry->h_addr_list[0], sizeof(struct in_addr));
            printf("   %s -> %s (%.2f ms)\n", test_domains[i], inet_ntoa(addr), time_taken);
        } else {
            printf("   %s -> FAILED (%.2f ms)\n", test_domains[i], time_taken);
        }
    }
}

int main(int argc, char *argv[]) {
    printf("DNS Override Test Application - Upstream DNS Server Testing\n");
    printf("==========================================================\n");
    
    // Check if LD_PRELOAD is set
    char *ld_preload = getenv("LD_PRELOAD");
    if (ld_preload && strstr(ld_preload, "dns_override.so")) {
        printf("✓ DNS override library is loaded via LD_PRELOAD\n");
        printf("  This means DNS queries will use your custom upstream servers\n");
    } else {
        printf("⚠ DNS override library is NOT loaded\n");
        printf("  DNS queries will use system default servers\n");
        printf("  To enable override: LD_PRELOAD=./dns_override.so %s\n", argv[0]);
    }
    
    // Show system DNS info
    print_system_dns_info();
    
    // Test basic DNS resolution
    printf("\n" "=== Basic DNS Resolution Tests ===\n");
    test_gethostbyname("google.com");
    test_getaddrinfo("google.com", "80");
    test_getaddrinfo("github.com", "443");
    
    // Test multiple domains quickly
    test_multiple_domains();
    
    // Performance test
    printf("\n" "=== Performance Test ===\n");
    printf("This will help you compare DNS server performance\n");
    test_dns_performance("google.com", 5);
    
    // Test IPv6 if available
    printf("\n" "=== IPv6 Test ===\n");
    test_getaddrinfo("ipv6.google.com", NULL);
    
    // Test non-existent domain
    printf("\n" "=== Error Handling Test ===\n");
    test_gethostbyname("this-domain-should-not-exist-12345.com");
    
    printf("\n" "=== Test Summary ===\n");
    if (ld_preload && strstr(ld_preload, "dns_override.so")) {
        printf("✓ Tests completed using custom DNS servers\n");
        printf("  Check the debug output above to see which DNS servers were used\n");
        printf("  Compare performance with system default by running without LD_PRELOAD\n");
    } else {
        printf("✓ Tests completed using system default DNS servers\n");
        printf("  To test with custom DNS servers:\n");
        printf("  1. Run: ./dns_config.sh preset cloudflare  (or another preset)\n");
        printf("  2. Run: LD_PRELOAD=./dns_override.so %s\n", argv[0]);
    }
    
    printf("\n" "Useful commands to try:\n");
    printf("  ./dns_config.sh status           - Show current configuration\n");
    printf("  ./dns_config.sh preset google    - Use Google DNS (8.8.8.8)\n");
    printf("  ./dns_config.sh preset cloudflare - Use Cloudflare DNS (1.1.1.1)\n");
    printf("  ./dns_config.sh test             - Compare system vs override\n");
    printf("  ./dns_config.sh enable-dns64     - Enable DNS64 synthesis\n");
    printf("  ./dns_config.sh test-dns64       - Test DNS64 functionality\n");
    
    return 0;
}
