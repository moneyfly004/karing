//go:build android

package clashmicore

import (
	"encoding/json"
	"net"
	"net/netip"
	"net/url"
	"slices"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/metacubex/mihomo/log"
	"tailscale.com/net/netns"
	"tailscale.com/net/tshttpproxy"
)

var (
	tailscaleDNSMu      sync.RWMutex
	tailscaleDNSServers []string

	tailscaleProxyMu          sync.RWMutex
	tailscaleProxyURL         string
	tailscaleSocketProtector  SocketProtector
	tailscaleNetnsProtected   bool
	tailscaleNetnsProxyURL    string
	tailscaleProxyInstallOnce sync.Once
	tailscaleProxyInstallErr  error
	tailscaleProxySelectCount atomic.Uint64
)

type androidNetworkDNSInfo struct {
	Interfaces []struct {
		DNSServers []string `json:"dnsServers"`
	} `json:"interfaces"`
}

func setTailscaleSocketProtector(protector SocketProtector) {
	tailscaleProxyMu.Lock()
	tailscaleSocketProtector = protector
	applyTailscaleNetnsProtectorLocked()
	tailscaleProxyMu.Unlock()
}

func setTailscaleAndroidDNSServersFromRaw(raw string) bool {
	var info androidNetworkDNSInfo
	if err := json.Unmarshal([]byte(raw), &info); err != nil {
		log.Warnln("[ClashMiCore] parse Android physical DNS servers failed: %v", err)
		return false
	}

	seen := map[string]struct{}{}
	servers := make([]string, 0)
	for _, iface := range info.Interfaces {
		for _, value := range iface.DNSServers {
			server, ok := normalizeTailscaleDNSServer(value)
			if !ok {
				continue
			}
			if _, exists := seen[server]; exists {
				continue
			}
			seen[server] = struct{}{}
			servers = append(servers, server)
		}
	}

	tailscaleDNSMu.Lock()
	changed := !slices.Equal(tailscaleDNSServers, servers)
	tailscaleDNSServers = servers
	tailscaleDNSMu.Unlock()

	if len(servers) == 0 {
		log.Warnln("[ClashMiCore] no Android physical DNS servers found for Mihomo DNS bootstrap")
		return changed
	}
	log.Infoln("[ClashMiCore] Android physical DNS servers updated: %s", strings.Join(servers, ","))
	return changed
}

func setTailscaleControlHTTPProxy(proxyURL string) {
	proxyURL = strings.TrimSpace(proxyURL)

	// The proxy hook must be installed before enabling the Android netns protector.
	//
	// Tailscale's control client asks tshttpproxy for an HTTP proxy before it
	// dials controlplane.tailscale.com. If the hook is missing while netns
	// protection is enabled, Android's VpnService.protect would let the
	// controlplane socket escape the VPN and bypass Mihomo rules. That is the
	// old registration regression this guard is meant to prevent.
	tailscaleProxyInstallOnce.Do(func() {
		tailscaleProxyInstallErr = tshttpproxy.SetProxyFunc(tailscaleProxyFromConfig)
	})
	if tailscaleProxyInstallErr != nil {
		log.Warnln("[ClashMiCore] install Tailscale control proxy hook failed: %v", tailscaleProxyInstallErr)
		tailscaleProxyMu.Lock()
		tailscaleProxyURL = ""
		applyTailscaleNetnsProtectorLocked()
		tailscaleProxyMu.Unlock()
		return
	}

	tailscaleProxyMu.Lock()
	changed := tailscaleProxyURL != proxyURL
	tailscaleProxyURL = proxyURL
	applyTailscaleNetnsProtectorLocked()
	tailscaleProxyMu.Unlock()

	if !changed {
		return
	}
	if proxyURL == "" {
		log.Warnln("[ClashMiCore] Tailscale control proxy disabled; no local HTTP proxy port found")
		return
	}
	log.Infoln("[ClashMiCore] Tailscale control proxy set to %s", redactedProxyURL(proxyURL))
}

func applyTailscaleNetnsProtectorLocked() {
	// Keep this helper as the single place that decides whether Tailscale's
	// Android netns hook is active.
	//
	// There are two competing requirements:
	//   1. controlplane.tailscale.com registration must be able to go through
	//      Mihomo, so user proxy rules can decide how Tailscale logs in.
	//   2. Tailscale's peer/DERP/netcheck sockets need Android VPN protection
	//      when possible, otherwise mobile networks with usable IPv6 may still
	//      look non-direct and fall back to DERP relay.
	//
	// The safe compromise is conditional: enable netns protection only after
	// the Tailscale HTTP proxy hook points control traffic at the local Mihomo
	// HTTP proxy. Do not change this to an unconditional SetAndroidProtectFunc
	// install, because that can bypass Mihomo for registration. Do not change it
	// back to unconditional nil either, because that breaks direct path probing.
	if tailscaleSocketProtector == nil {
		netns.SetAndroidProtectFunc(nil)
		if tailscaleNetnsProtected {
			log.Warnln("[ClashMiCore] Tailscale Android netns protector cleared")
		}
		tailscaleNetnsProtected = false
		tailscaleNetnsProxyURL = ""
		return
	}

	if tailscaleProxyURL == "" {
		netns.SetAndroidProtectFunc(nil)
		if tailscaleNetnsProtected {
			log.Warnln("[ClashMiCore] Tailscale Android netns protector disabled; no local control proxy is configured")
		} else {
			log.Infoln("[ClashMiCore] Tailscale Android netns protector deferred; keeping Tailscale control traffic inside VPN until a local control proxy is configured")
		}
		tailscaleNetnsProtected = false
		tailscaleNetnsProxyURL = ""
		return
	}

	protector := tailscaleSocketProtector
	proxyURL := tailscaleProxyURL
	netns.SetAndroidProtectFunc(func(fd int) error {
		return protectSocketFD(protector, uintptr(fd), "tailscale-netns", "")
	})
	if !tailscaleNetnsProtected || tailscaleNetnsProxyURL != proxyURL {
		log.Infoln("[ClashMiCore] Tailscale Android netns protector installed for peer/DERP path discovery; control proxy=%s", redactedProxyURL(proxyURL))
	}
	tailscaleNetnsProtected = true
	tailscaleNetnsProxyURL = proxyURL
}

func tailscaleProxyFromConfig(target *url.URL) (*url.URL, error) {
	tailscaleProxyMu.RLock()
	raw := tailscaleProxyURL
	tailscaleProxyMu.RUnlock()
	if raw == "" {
		return nil, nil
	}
	proxyURL, err := url.Parse(raw)
	if err != nil {
		log.Warnln("[ClashMiCore] parse Tailscale control proxy failed target=%s proxy=%s error=%v", target.Redacted(), redactedProxyURL(raw), err)
		return nil, err
	}
	count := tailscaleProxySelectCount.Add(1)
	if count <= 8 || count%50 == 0 {
		log.Infoln("[ClashMiCore] Tailscale control proxy selected target=%s proxy=%s count=%d", target.Redacted(), proxyURL.Redacted(), count)
	}
	return proxyURL, nil
}

func redactedProxyURL(raw string) string {
	proxyURL, err := url.Parse(raw)
	if err != nil {
		return "<invalid>"
	}
	return proxyURL.Redacted()
}

func normalizeTailscaleDNSServer(value string) (string, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", false
	}
	if host, port, err := net.SplitHostPort(value); err == nil {
		if port == "" {
			port = "53"
		}
		if addr, err := netip.ParseAddr(strings.Trim(host, "[]")); err == nil {
			return net.JoinHostPort(addr.String(), port), true
		}
		return "", false
	}
	if addr, err := netip.ParseAddr(strings.Trim(value, "[]")); err == nil {
		return net.JoinHostPort(addr.String(), "53"), true
	}
	return "", false
}

func androidPhysicalDNSServers() []string {
	tailscaleDNSMu.RLock()
	defer tailscaleDNSMu.RUnlock()
	return append([]string(nil), tailscaleDNSServers...)
}
