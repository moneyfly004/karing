//go:build !android

package clashmicore

func setTailscaleSocketProtector(SocketProtector) {}

func setTailscaleAndroidDNSServersFromRaw(string) bool { return false }

func setTailscaleControlHTTPProxy(string) {}

func androidPhysicalDNSServers() []string { return nil }
