package clashmicore

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	mihomoDNS "github.com/metacubex/mihomo/dns"
	"gopkg.in/yaml.v3"
)

func TestBuildRuntimeConfigDefaultsToSystemTunStack(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", "mixed-port: 7890\nipv6: true\n")

	out, err := buildRuntimeConfig(configFile, "", "", 123)
	if err != nil {
		t.Fatal(err)
	}

	tun := readTunMapping(t, out)
	assertScalar(t, tun, "enable", "true")
	assertScalar(t, tun, "file-descriptor", "123")
	assertScalar(t, tun, "stack", defaultAndroidTunStack)
	assertScalar(t, tun, "auto-route", "false")
	assertScalar(t, tun, "auto-detect-interface", "false")
	assertSequence(t, tun, "inet6-address", []string{androidTunIPv6Address})

	dns := readMapping(t, out, "dns")
	assertScalar(t, dns, "fake-ip-range", androidTunFakeIPRange)
}

func TestBuildRuntimeConfigDoesNotForceIPv6WhenDisabled(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", "mixed-port: 7890\nipv6: false\n")

	out, err := buildRuntimeConfig(configFile, "", "", 321)
	if err != nil {
		t.Fatal(err)
	}

	tun := readTunMapping(t, out)
	if value := findValue(tun, "inet6-address"); value != nil {
		t.Fatalf("inet6-address = %v, want nil when ipv6 is disabled", value.Value)
	}
}

func TestEffectiveIPv6UsesMergedConfig(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", "mixed-port: 7890\nipv6: false\n")
	patchFile := writeTempFile(t, "patch.yaml", "ipv6: true\n")

	enabled, err := EffectiveIPv6(configFile, patchFile, "")
	if err != nil {
		t.Fatal(err)
	}
	if !enabled {
		t.Fatal("EffectiveIPv6 = false, want true from merged patch")
	}
}

func TestEffectiveIPv6HonorsFinalPatchOverride(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", "mixed-port: 7890\nipv6: true\n")
	finalPatchFile := writeTempFile(t, "final.json", "{\n  \"ipv6\": false\n}\n")

	enabled, err := EffectiveIPv6(configFile, "", finalPatchFile)
	if err != nil {
		t.Fatal(err)
	}
	if enabled {
		t.Fatal("EffectiveIPv6 = true, want false from final patch")
	}
}

func TestBuildRuntimeConfigPreservesRequestedTunStack(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", "mixed-port: 7890\ndns:\n  fake-ip-range: 198.18.0.8/16\n")
	patchFile := writeTempFile(t, "patch.yaml", "tun:\n  stack: gvisor\n")

	out, err := buildRuntimeConfig(configFile, "", patchFile, 456)
	if err != nil {
		t.Fatal(err)
	}

	tun := readTunMapping(t, out)
	assertScalar(t, tun, "stack", "gvisor")
	assertScalar(t, tun, "file-descriptor", "456")

	dns := readMapping(t, out, "dns")
	assertScalar(t, dns, "fake-ip-range", androidTunFakeIPRange)
}

func TestBuildRuntimeConfigDoesNotInferTailscaleControlPolicy(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
mixed-port: 7890
proxies:
  - name: ts-mihomo
    type: tailscale
  - name: us-node
    type: vless
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - us-node
      - DIRECT
rules:
  - IP-CIDR,192.168.6.0/24,ts-mihomo
  - MATCH,DIRECT
`)

	out, err := buildRuntimeConfig(configFile, "", "", 123)
	if err != nil {
		t.Fatal(err)
	}

	rules := readSequence(t, out, "rules")
	assertSequenceValues(t, rules, []string{
		"IP-CIDR,192.168.6.0/24,ts-mihomo",
		"MATCH,DIRECT",
	})
}

func TestBuildRuntimeConfigKeepsConfiguredTailscaleControlRule(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
mixed-port: 7890
proxies:
  - name: ts-mihomo
    type: tailscale
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - DIRECT
rules:
  - DOMAIN,controlplane.tailscale.com,custom
  - IP-CIDR,192.168.6.0/24,ts-mihomo
`)

	out, err := buildRuntimeConfig(configFile, "", "", 123)
	if err != nil {
		t.Fatal(err)
	}

	rules := readSequence(t, out, "rules")
	assertSequenceValues(t, rules, []string{
		"DOMAIN,controlplane.tailscale.com,custom",
		"IP-CIDR,192.168.6.0/24,ts-mihomo",
	})
}

func TestAndroidPhysicalNameserverURLEscapesIPv6Zone(t *testing.T) {
	got := androidPhysicalNameserverURL("[fe80::1%wlan0]:53")
	want := "udp://[fe80::1%25wlan0]:53#DIRECT"
	if got != want {
		t.Fatalf("nameserver URL = %q, want %q", got, want)
	}
}

func TestAndroidPhysicalNameserverURLBypassesRespectRules(t *testing.T) {
	raw := []byte(`
dns:
  enable: true
  respect-rules: true
  nameserver:
    - 1.1.1.1
  proxy-server-nameserver:
    - 9.9.9.9
  nameserver-policy:
    controlplane.tailscale.com:
      - "` + androidPhysicalNameserverURL("8.8.8.8:53") + `"
`)

	cfg, err := config.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg.DNS.NameServer) == 0 || cfg.DNS.NameServer[0].ProxyName != mihomoDNS.RespectRules {
		t.Fatalf("main nameserver proxy = %#v, want respect-rules active", cfg.DNS.NameServer)
	}
	if len(cfg.DNS.NameServerPolicy) != 1 {
		t.Fatalf("policy count = %d, want 1", len(cfg.DNS.NameServerPolicy))
	}
	nameservers := cfg.DNS.NameServerPolicy[0].NameServers
	if len(nameservers) != 1 {
		t.Fatalf("policy nameserver count = %d, want 1", len(nameservers))
	}
	if nameservers[0].ProxyName != androidPhysicalDNSProxyName {
		t.Fatalf("policy nameserver proxy = %q, want %q", nameservers[0].ProxyName, androidPhysicalDNSProxyName)
	}
}

func TestInjectAndroidTailscaleDNSPolicyDoesNotChangeMainNameservers(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
dns:
  nameserver:
    - https://private.example/dns-query
proxies:
  - name: ts-mihomo
    type: tailscale
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}
	dns := findValue(root, "dns")

	injectAndroidTailscaleDNSPolicyWithServers(root, dns, []string{"[fe80::1%wlan0]:53", "8.8.8.8:53"})

	assertSequenceValues(t, findValue(dns, "nameserver"), []string{"https://private.example/dns-query"})
	policy := findValue(dns, "nameserver-policy")
	if policy == nil || policy.Kind != yaml.MappingNode {
		t.Fatalf("nameserver-policy missing or invalid: %#v", policy)
	}
	assertSequenceValues(t, findValue(policy, "controlplane.tailscale.com"), []string{
		"udp://[fe80::1%25wlan0]:53#DIRECT",
		"udp://8.8.8.8:53#DIRECT",
	})
}

func TestInjectAndroidTailscaleDNSPolicyPreservesExistingPolicy(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
dns:
  nameserver-policy:
    controlplane.tailscale.com:
      - https://private.example/dns-query
proxies:
  - name: ts-mihomo
    type: tailscale
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}
	dns := findValue(root, "dns")

	injectAndroidTailscaleDNSPolicyWithServers(root, dns, []string{"8.8.8.8:53"})

	policy := findValue(dns, "nameserver-policy")
	assertSequenceValues(t, findValue(policy, "controlplane.tailscale.com"), []string{"https://private.example/dns-query"})
}

func TestInjectAndroidTailscaleDNSPolicyPreservesExistingSuffixPolicy(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
dns:
  nameserver-policy:
    +.tailscale.com:
      - https://private.example/dns-query
proxies:
  - name: ts-mihomo
    type: tailscale
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}
	dns := findValue(root, "dns")

	injectAndroidTailscaleDNSPolicyWithServers(root, dns, []string{"8.8.8.8:53"})

	policy := findValue(dns, "nameserver-policy")
	assertSequenceValues(t, findValue(policy, "+.tailscale.com"), []string{"https://private.example/dns-query"})
	if value := findValue(policy, "controlplane.tailscale.com"); value != nil {
		t.Fatalf("controlplane.tailscale.com policy = %#v, want nil when suffix policy exists", value)
	}
}

func TestInjectAndroidTailscaleDNSPolicyPreservesExistingWildcardPolicy(t *testing.T) {
	for _, policyKey := range []string{"*.tailscale.com", ".tailscale.com"} {
		t.Run(policyKey, func(t *testing.T) {
			configFile := writeTempFile(t, "config.yaml", `
dns:
  nameserver-policy:
    "`+policyKey+`":
      - https://private.example/dns-query
proxies:
  - name: ts-mihomo
    type: tailscale
`)
			root, err := readYamlMapping(configFile, true)
			if err != nil {
				t.Fatal(err)
			}
			dns := findValue(root, "dns")

			hosts := injectAndroidTailscaleDNSPolicyWithServers(root, dns, []string{"8.8.8.8:53"})

			if hosts != nil {
				t.Fatalf("tracked hosts = %v, want nil when wildcard policy exists", hosts)
			}
			policy := findValue(dns, "nameserver-policy")
			assertSequenceValues(t, findValue(policy, policyKey), []string{"https://private.example/dns-query"})
			if value := findValue(policy, "controlplane.tailscale.com"); value != nil {
				t.Fatalf("controlplane.tailscale.com policy = %#v, want nil when wildcard policy exists", value)
			}
		})
	}
}

func TestInjectAndroidTailscaleDNSPolicyScansInlineProviderPayload(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
dns:
  nameserver:
    - https://private.example/dns-query
proxy-providers:
  ts-provider:
    type: inline
    payload:
      - name: ts-mihomo
        type: tailscale
        control-url: https://login.example.com
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}
	dns := findValue(root, "dns")

	injectAndroidTailscaleDNSPolicyWithServers(root, dns, []string{"8.8.8.8:53"})

	assertSequenceValues(t, findValue(dns, "nameserver"), []string{"https://private.example/dns-query"})
	policy := findValue(dns, "nameserver-policy")
	if policy == nil || policy.Kind != yaml.MappingNode {
		t.Fatalf("nameserver-policy missing or invalid: %#v", policy)
	}
	assertSequenceValues(t, findValue(policy, "login.example.com"), []string{"udp://8.8.8.8:53#DIRECT"})
}

func TestInjectAndroidTailscaleDNSPolicyTracksHostsWithoutServers(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
dns:
  nameserver:
    - https://private.example/dns-query
proxies:
  - name: ts-mihomo
    type: tailscale
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}
	dns := findValue(root, "dns")

	hosts := injectAndroidTailscaleDNSPolicyWithServers(root, dns, nil)

	assertStringSlice(t, hosts, []string{"controlplane.tailscale.com"})
	if value := findValue(dns, "nameserver-policy"); value != nil {
		t.Fatalf("nameserver-policy = %#v, want nil without physical DNS servers", value)
	}
}

func TestReplaceDNSPoliciesForHostsRefreshesOnlyInjectedPolicies(t *testing.T) {
	policies := []mihomoDNS.Policy{
		{
			Domain:      "controlplane.tailscale.com",
			NameServers: []mihomoDNS.NameServer{{Net: "udp", Addr: "1.1.1.1:53"}},
		},
		{
			Domain:      "private.example",
			NameServers: []mihomoDNS.NameServer{{Net: "https", Addr: "private.example/dns-query"}},
		},
	}
	refreshed := []mihomoDNS.NameServer{{Net: "udp", Addr: "8.8.8.8:53"}}

	got := replaceDNSPoliciesForHosts(policies, []string{"CONTROLPLANE.TAILSCALE.COM", "login.example.com"}, refreshed)

	if len(got) != 3 {
		t.Fatalf("policy count = %d, want 3", len(got))
	}
	assertPolicyNameserver(t, got[0], "controlplane.tailscale.com", "8.8.8.8:53")
	assertPolicyNameserver(t, got[1], "private.example", "private.example/dns-query")
	assertPolicyNameserver(t, got[2], "login.example.com", "8.8.8.8:53")
}

func TestReplaceDNSPoliciesForHostsRemovesInjectedPoliciesWithoutServers(t *testing.T) {
	policies := []mihomoDNS.Policy{
		{
			Domain:      "controlplane.tailscale.com",
			NameServers: []mihomoDNS.NameServer{{Net: "udp", Addr: "1.1.1.1:53"}},
		},
		{
			Domain:      "private.example",
			NameServers: []mihomoDNS.NameServer{{Net: "https", Addr: "private.example/dns-query"}},
		},
	}

	got := replaceDNSPoliciesForHosts(policies, []string{"controlplane.tailscale.com"}, nil)

	if len(got) != 1 {
		t.Fatalf("policy count = %d, want 1", len(got))
	}
	assertPolicyNameserver(t, got[0], "private.example", "private.example/dns-query")
}

func TestSyncRuntimeConfigStateFromAppliedConfigRefreshesDNSCache(t *testing.T) {
	resetRuntimeConfigStateForTest(t)
	setRuntimeConfigState(
		&config.DNS{
			Enable: true,
			NameServerPolicy: []mihomoDNS.Policy{{
				Domain:      "old.example",
				NameServers: []mihomoDNS.NameServer{{Net: "udp", Addr: "1.1.1.1:53"}},
			}},
		},
		false,
		[]string{"controlplane.tailscale.com"},
	)

	syncRuntimeConfigStateFromAppliedConfigWithServers(&config.Config{
		DNS: &config.DNS{
			Enable: true,
			NameServerPolicy: []mihomoDNS.Policy{{
				Domain:      "private.example",
				NameServers: []mihomoDNS.NameServer{{Net: "https", Addr: "private.example/dns-query"}},
			}},
		},
		General: &config.General{IPv6: true},
		Proxies: map[string]C.Proxy{
			"ts": newTailscaleTestProxy(""),
		},
	}, nil)

	dnsConfig, generalIPv6, hosts := runtimeConfigStateForTest()
	if !generalIPv6 {
		t.Fatal("general IPv6 cache = false, want true")
	}
	assertStringSlice(t, hosts, []string{"controlplane.tailscale.com"})
	if len(dnsConfig.NameServerPolicy) != 1 {
		t.Fatalf("policy count = %d, want 1", len(dnsConfig.NameServerPolicy))
	}
	assertPolicyNameserver(t, dnsConfig.NameServerPolicy[0], "private.example", "private.example/dns-query")
}

func TestSyncRuntimeConfigStateFromAppliedConfigReappliesTrackedPolicies(t *testing.T) {
	resetRuntimeConfigStateForTest(t)
	setRuntimeConfigState(&config.DNS{Enable: true}, false, []string{"controlplane.tailscale.com"})

	syncRuntimeConfigStateFromAppliedConfigWithServers(&config.Config{
		DNS: &config.DNS{
			Enable:     true,
			NameServer: []mihomoDNS.NameServer{{Net: "udp", Addr: "9.9.9.9:53"}},
		},
		General: &config.General{IPv6: true},
		Proxies: map[string]C.Proxy{
			"ts": newTailscaleTestProxy(""),
		},
	}, []string{"8.8.8.8:53"})

	dnsConfig, _, hosts := runtimeConfigStateForTest()
	assertStringSlice(t, hosts, []string{"controlplane.tailscale.com"})
	if len(dnsConfig.NameServerPolicy) != 1 {
		t.Fatalf("policy count = %d, want 1", len(dnsConfig.NameServerPolicy))
	}
	assertPolicyNameserver(t, dnsConfig.NameServerPolicy[0], "controlplane.tailscale.com", "8.8.8.8:53")
}

func TestSyncRuntimeConfigStateFromAppliedConfigRecomputesTailscaleControlHosts(t *testing.T) {
	resetRuntimeConfigStateForTest(t)
	setRuntimeConfigState(&config.DNS{Enable: true}, false, nil)

	syncRuntimeConfigStateFromAppliedConfigWithServers(&config.Config{
		DNS: &config.DNS{
			Enable:     true,
			NameServer: []mihomoDNS.NameServer{{Net: "udp", Addr: "9.9.9.9:53"}},
		},
		General: &config.General{IPv6: true},
		Proxies: map[string]C.Proxy{
			"ts": newTailscaleTestProxy("https://login.example.com"),
		},
	}, []string{"8.8.8.8:53"})

	dnsConfig, _, hosts := runtimeConfigStateForTest()
	assertStringSlice(t, hosts, []string{"login.example.com"})
	if len(dnsConfig.NameServerPolicy) != 1 {
		t.Fatalf("policy count = %d, want 1", len(dnsConfig.NameServerPolicy))
	}
	assertPolicyNameserver(t, dnsConfig.NameServerPolicy[0], "login.example.com", "8.8.8.8:53")
}

func TestMergeStartupRuntimeConfigStatePreservesHookDiscoveredHosts(t *testing.T) {
	resetRuntimeConfigStateForTest(t)
	setRuntimeConfigState(&config.DNS{
		Enable: true,
		NameServerPolicy: []mihomoDNS.Policy{{
			Domain:      "login.example.com",
			NameServers: []mihomoDNS.NameServer{{Net: "udp", Addr: "8.8.8.8:53", ProxyName: androidPhysicalDNSProxyName}},
		}},
	}, true, []string{"login.example.com"})

	mergeStartupRuntimeConfigState(&config.DNS{Enable: true}, true, nil)

	dnsConfig, _, hosts := runtimeConfigStateForTest()
	assertStringSlice(t, hosts, []string{"login.example.com"})
	if len(dnsConfig.NameServerPolicy) != 1 {
		t.Fatalf("policy count = %d, want 1", len(dnsConfig.NameServerPolicy))
	}
	assertPolicyNameserver(t, dnsConfig.NameServerPolicy[0], "login.example.com", "8.8.8.8:53")
}

func TestMergeStartupRuntimeConfigStateAddsInjectedHosts(t *testing.T) {
	resetRuntimeConfigStateForTest(t)
	setRuntimeConfigState(&config.DNS{Enable: true}, true, []string{"login.example.com"})

	mergeStartupRuntimeConfigState(&config.DNS{Enable: true}, true, []string{"controlplane.tailscale.com", "LOGIN.EXAMPLE.COM"})

	_, _, hosts := runtimeConfigStateForTest()
	assertStringSlice(t, hosts, []string{"login.example.com", "controlplane.tailscale.com"})
}

func TestSyncRuntimeConfigStateFromAppliedConfigStopsTrackingCoveredHosts(t *testing.T) {
	resetRuntimeConfigStateForTest(t)
	setRuntimeConfigState(&config.DNS{Enable: true}, false, []string{"controlplane.tailscale.com"})

	syncRuntimeConfigStateFromAppliedConfigWithServers(&config.Config{
		DNS: &config.DNS{
			Enable: true,
			NameServerPolicy: []mihomoDNS.Policy{{
				Domain:      "*.tailscale.com",
				NameServers: []mihomoDNS.NameServer{{Net: "https", Addr: "private.example/dns-query"}},
			}},
		},
		General: &config.General{IPv6: true},
		Proxies: map[string]C.Proxy{
			"ts": newTailscaleTestProxy(""),
		},
	}, nil)

	_, _, hosts := runtimeConfigStateForTest()
	if hosts != nil {
		t.Fatalf("tracked hosts = %v, want nil when live DNS policy covers host", hosts)
	}
}

func TestFindLocalHTTPProxyURLIncludesAuthentication(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
mixed-port: 7890
authentication:
  - user:p@ss:with:colon
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}

	got := findLocalHTTPProxyURL(root)
	want := "http://user:p%40ss%3Awith%3Acolon@127.0.0.1:7890"
	if got != want {
		t.Fatalf("proxy URL = %q, want %q", got, want)
	}
}

func TestFindLocalHTTPProxyURLUsesConfiguredBindAddress(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
allow-lan: true
bind-address: 192.168.6.10
mixed-port: 7890
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}

	got := findLocalHTTPProxyURL(root)
	want := "http://192.168.6.10:7890"
	if got != want {
		t.Fatalf("proxy URL = %q, want %q", got, want)
	}
}

func TestFindLocalHTTPProxyURLKeepsLoopbackForWildcardBindAddress(t *testing.T) {
	configFile := writeTempFile(t, "config.yaml", `
allow-lan: true
bind-address: "*"
mixed-port: 7890
`)
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		t.Fatal(err)
	}

	got := findLocalHTTPProxyURL(root)
	want := "http://127.0.0.1:7890"
	if got != want {
		t.Fatalf("proxy URL = %q, want %q", got, want)
	}
}

func TestFindLocalHTTPProxyURLFromGeneralUsesReloadedConfig(t *testing.T) {
	got := findLocalHTTPProxyURLFromGeneral(&config.General{
		Inbound: config.Inbound{
			MixedPort:      7891,
			AllowLan:       true,
			BindAddress:    "192.168.6.10",
			Authentication: []string{"user:p@ss"},
		},
	})
	want := "http://user:p%40ss@192.168.6.10:7891"
	if got != want {
		t.Fatalf("proxy URL = %q, want %q", got, want)
	}
}

func TestProtectSocketUsesRawFd(t *testing.T) {
	protector := &recordingProtector{ok: true}
	conn := fakeRawConn{fd: 42}

	if err := protectSocket(protector, "tcp", "example.com:443", conn); err != nil {
		t.Fatal(err)
	}
	if protector.fd != 42 {
		t.Fatalf("protected fd = %d, want 42", protector.fd)
	}
}

func TestSetSocketProtectorInstallsDialerHook(t *testing.T) {
	oldHook := dialer.DefaultSocketHook
	t.Cleanup(func() {
		dialer.DefaultSocketHook = oldHook
	})

	protector := &recordingProtector{ok: true}
	SetSocketProtector(protector)

	if dialer.DefaultSocketHook == nil {
		t.Fatal("expected mihomo dialer socket hook to be installed")
	}
	if err := dialer.DefaultSocketHook("tcp", "example.com:443", fakeRawConn{fd: 99}); err != nil {
		t.Fatal(err)
	}
	if protector.fd != 99 {
		t.Fatalf("protected fd = %d, want 99", protector.fd)
	}

	SetSocketProtector(nil)
	if dialer.DefaultSocketHook != nil {
		t.Fatal("expected mihomo dialer socket hook to be cleared")
	}
}

func TestProtectSocketReportsFalseResult(t *testing.T) {
	protector := &recordingProtector{ok: false}

	err := protectSocket(protector, "tcp", "example.com:443", fakeRawConn{fd: 7})
	if err == nil {
		t.Fatal("expected protect error")
	}
}

func TestProtectSocketReportsControlError(t *testing.T) {
	wantErr := errors.New("control failed")
	err := protectSocket(&recordingProtector{ok: true}, "udp", "1.1.1.1:53", fakeRawConn{err: wantErr})
	if !errors.Is(err, wantErr) {
		t.Fatalf("error = %v, want wrapping %v", err, wantErr)
	}
}

func writeTempFile(t *testing.T, name string, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func readTunMapping(t *testing.T, data []byte) *yaml.Node {
	return readMapping(t, data, "tun")
}

func readMapping(t *testing.T, data []byte, key string) *yaml.Node {
	t.Helper()
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatal(err)
	}
	root := doc.Content[0]
	mapping := findValue(root, key)
	if mapping == nil || mapping.Kind != yaml.MappingNode {
		t.Fatalf("%s mapping missing: %s", key, string(data))
	}
	return mapping
}

func readSequence(t *testing.T, data []byte, key string) *yaml.Node {
	t.Helper()
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		t.Fatal(err)
	}
	root := doc.Content[0]
	sequence := findValue(root, key)
	if sequence == nil || sequence.Kind != yaml.SequenceNode {
		t.Fatalf("%s sequence missing: %s", key, string(data))
	}
	return sequence
}

func assertScalar(t *testing.T, root *yaml.Node, key string, want string) {
	t.Helper()
	value := findValue(root, key)
	if value == nil {
		t.Fatalf("missing key %q", key)
	}
	if value.Value != want {
		t.Fatalf("%s = %q, want %q", key, value.Value, want)
	}
}

func assertSequenceValues(t *testing.T, sequence *yaml.Node, want []string) {
	t.Helper()
	if len(sequence.Content) != len(want) {
		t.Fatalf("sequence length = %d, want %d", len(sequence.Content), len(want))
	}
	for i, item := range sequence.Content {
		if item.Value != want[i] {
			t.Fatalf("sequence[%d] = %q, want %q", i, item.Value, want[i])
		}
	}
}

func assertPolicyNameserver(t *testing.T, policy mihomoDNS.Policy, wantDomain string, wantAddr string) {
	t.Helper()
	if policy.Domain != wantDomain {
		t.Fatalf("policy domain = %q, want %q", policy.Domain, wantDomain)
	}
	if len(policy.NameServers) != 1 {
		t.Fatalf("policy nameserver count = %d, want 1", len(policy.NameServers))
	}
	if policy.NameServers[0].Addr != wantAddr {
		t.Fatalf("policy nameserver addr = %q, want %q", policy.NameServers[0].Addr, wantAddr)
	}
}

func resetRuntimeConfigStateForTest(t *testing.T) {
	t.Helper()
	runtimeConfigMu.Lock()
	lastDNSConfig = nil
	lastGeneralIPv6 = false
	lastDNSPolicyHosts = nil
	runtimeConfigMu.Unlock()
	t.Cleanup(func() {
		runtimeConfigMu.Lock()
		lastDNSConfig = nil
		lastGeneralIPv6 = false
		lastDNSPolicyHosts = nil
		runtimeConfigMu.Unlock()
	})
}

func runtimeConfigStateForTest() (*config.DNS, bool, []string) {
	runtimeConfigMu.Lock()
	defer runtimeConfigMu.Unlock()
	return cloneDNSConfig(lastDNSConfig), lastGeneralIPv6, append([]string(nil), lastDNSPolicyHosts...)
}

func newTailscaleTestProxy(controlURL string) C.Proxy {
	return adapter.NewProxy(fakeTailscaleAdapter{controlURL: controlURL})
}

type fakeTailscaleAdapter struct {
	controlURL string
}

func (f fakeTailscaleAdapter) Name() string { return "ts" }

func (f fakeTailscaleAdapter) Type() C.AdapterType { return C.Tailscale }

func (f fakeTailscaleAdapter) Addr() string { return "tailscale" }

func (f fakeTailscaleAdapter) SupportUDP() bool { return true }

func (f fakeTailscaleAdapter) ProxyInfo() C.ProxyInfo { return C.ProxyInfo{} }

func (f fakeTailscaleAdapter) MarshalJSON() ([]byte, error) { return []byte(`{}`), nil }

func (f fakeTailscaleAdapter) DialContext(context.Context, *C.Metadata) (C.Conn, error) {
	return nil, syscall.ENOSYS
}

func (f fakeTailscaleAdapter) ListenPacketContext(context.Context, *C.Metadata) (C.PacketConn, error) {
	return nil, syscall.ENOSYS
}

func (f fakeTailscaleAdapter) SupportUOT() bool { return false }

func (f fakeTailscaleAdapter) IsL3Protocol(*C.Metadata) bool { return false }

func (f fakeTailscaleAdapter) Unwrap(*C.Metadata, bool) C.Proxy { return nil }

func (f fakeTailscaleAdapter) Close() error { return nil }

func (f fakeTailscaleAdapter) TailscaleControlURL() string { return f.controlURL }

func assertStringSlice(t *testing.T, got []string, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("slice length = %d, want %d", len(got), len(want))
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("slice[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

type recordingProtector struct {
	fd int64
	ok bool
}

func (p *recordingProtector) Protect(fd int64) bool {
	p.fd = fd
	return p.ok
}

type fakeRawConn struct {
	fd  uintptr
	err error
}

func (c fakeRawConn) Control(fn func(fd uintptr)) error {
	if c.err != nil {
		return c.err
	}
	fn(c.fd)
	return nil
}

func (c fakeRawConn) Read(func(fd uintptr) bool) error {
	return syscall.ENOSYS
}

func (c fakeRawConn) Write(func(fd uintptr) bool) error {
	return syscall.ENOSYS
}

func assertSequence(t *testing.T, root *yaml.Node, key string, want []string) {
	t.Helper()
	value := findValue(root, key)
	if value == nil {
		t.Fatalf("missing key %q", key)
	}
	if value.Kind != yaml.SequenceNode {
		t.Fatalf("%s kind = %v, want sequence", key, value.Kind)
	}
	if len(value.Content) != len(want) {
		t.Fatalf("%s length = %d, want %d", key, len(value.Content), len(want))
	}
	for i, item := range value.Content {
		if item.Value != want[i] {
			t.Fatalf("%s[%d] = %q, want %q", key, i, item.Value, want[i])
		}
	}
}
