import 'dart:io';

class NetworkUtils {
  /// Get the local network IP address of this machine, prioritizing WiFi interfaces
  static Future<String> getLocalIpAddress() async {
    try {
      // Get all network interfaces
      final interfaces = await NetworkInterface.list(
        includeLoopback: false, // Exclude localhost
      );

      // Look for the most appropriate interface in order of preference:
      // 1. WiFi interfaces (look for names containing 'wlan', 'wi', 'wireless', etc.)
      // 2. Ethernet interfaces (look for 'eth', 'en', etc.)
      // 3. Other interfaces that are on common local network ranges
      
      // First, try to find WiFi interfaces
      final wifiInterfaces = interfaces.where((interface) {
        final name = interface.name.toLowerCase();
        return name.contains('wlan') || 
               name.contains('wi') || 
               name.contains('wireless') || 
               name.contains('wifi') ||
               name.contains('wl');
      }).toList();
      
      // Look for WiFi IP addresses first
      for (final interface in wifiInterfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            final ip = address.address;
            if (_isLocalNetworkIp(ip)) {
              return ip;
            }
          }
        }
      }

      // If no WiFi interface found or it didn't have a valid IP, try other interfaces
      // Prioritizing interfaces that are on local network ranges
      for (final interface in interfaces) {
        // Skip if it's already a WiFi interface we checked
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('wi') || name.contains('wireless') || 
            name.contains('wifi') || name.contains('wl')) {
          continue; // Already checked
        }
        
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            final ip = address.address;
            if (_isLocalNetworkIp(ip)) {
              return ip;
            }
          }
        }
      }

      // If no appropriate IP found, return localhost as fallback
      return '127.0.0.1';
    } catch (e) {
      // If there's an error, fall back to the original method
      return await _getFallbackIpAddress();
    }
  }

  /// Fallback method to get an IP address using the original approach
  static Future<String> _getFallbackIpAddress() async {
    try {
      // Get all network interfaces
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false, // Exclude localhost
      );

      // Filter for non-localhost IPv4 addresses that are not private ranges
      // We prioritize common WiFi/local network ranges: 192.168.x.x, 10.x.x.x, 172.16-31.x.x
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            final ip = address.address;
            
            // Check if it's a local network IP (not public internet IP)
            if (_isLocalNetworkIp(ip)) {
              return ip;
            }
          }
        }
      }

      // If no local network IP found, return localhost as fallback
      return '127.0.0.1';
    } catch (e) {
      // If there's an error, fall back to localhost
      return '127.0.0.1';
    }
  }

  /// Check if an IP address is part of a local network range
  static bool _isLocalNetworkIp(String ip) {
    // Matches 192.168.x.x
    if (RegExp(r'^192\.168\.').hasMatch(ip)) {
      return true;
    }
    
    // Matches 10.x.x.x
    if (RegExp(r'^10\.').hasMatch(ip)) {
      return true;
    }
    
    // Matches 172.16.x.x to 172.31.x.x
    if (RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(ip)) {
      return true;
    }

    // Matches 169.254.x.x (link-local, but not what we want)
    if (RegExp(r'^169\.254\.').hasMatch(ip)) {
      return false;
    }

    // For any other IP that isn't clearly public, we'll consider it local
    // (This is a simplified check but should work for most LAN scenarios)
    return !RegExp(r'^(0|127|22[4-9]|23[0-9]|24[0-9]|25[0-5])\.').hasMatch(ip);
  }
}