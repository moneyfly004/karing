package clashmicore

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	mihomoResolver "github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/trie"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	mihomoDNS "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"gopkg.in/yaml.v3"
)

var (
	mu                 sync.Mutex
	runtimeConfigMu    sync.Mutex
	running            bool
	lastHome           string
	lastDNSConfig      *config.DNS
	lastGeneralIPv6    bool
	lastDNSPolicyHosts []string
)

type SocketProtector interface {
	Protect(fd int64) bool
}

func init() {
	executor.SetApplyConfigHook(syncRuntimeConfigStateFromAppliedConfig)
}

const androidTunMTU = 4064
const defaultAndroidTunStack = "system"
const androidTunFakeIPRange = "172.19.0.1/16"
const androidTunIPv6Address = "fdfe:dcbe:9876::1/126"
const androidPhysicalDNSProxyName = "DIRECT"

func SetSocketProtector(protector SocketProtector) {
	mu.Lock()
	defer mu.Unlock()

	if protector == nil {
		dialer.DefaultSocketHook = nil
		setTailscaleSocketProtector(nil)
		log.Warnln("[ClashMiCore] Android socket protector cleared")
		return
	}
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		return protectSocket(protector, network, address, conn)
	}
	setTailscaleSocketProtector(protector)
	log.Infoln("[ClashMiCore] Android socket protector installed for mihomo dialer and Tailscale netns")
}

func SetAndroidNetworkInfo(raw string) error {
	dnsChanged := setTailscaleAndroidDNSServersFromRaw(raw)
	if dnsChanged {
		if err := refreshAndroidTailscaleDNSPolicy(); err != nil {
			log.Warnln("[ClashMiCore] refresh Android physical DNS policy failed: %v", err)
			return err
		}
	}
	log.Infoln("[ClashMiCore] Android network info updated")
	return nil
}

func Start(configFile string, patchFile string, finalPatchFile string, homeDir string, tunFd int, externalController string, secret string) error {
	mu.Lock()
	defer mu.Unlock()

	if tunFd <= 0 {
		return errors.New("invalid tun fd")
	}
	ownsTunFd := true
	closeOwnedTunFd := func(reason string) {
		if !ownsTunFd {
			return
		}
		ownsTunFd = false
		if closeErr := syscall.Close(tunFd); closeErr != nil {
			log.Warnln("[ClashMiCore] close tun fd failed reason=%s fd=%d error=%v", reason, tunFd, closeErr)
			return
		}
		log.Warnln("[ClashMiCore] closed tun fd reason=%s fd=%d", reason, tunFd)
	}
	if configFile == "" {
		closeOwnedTunFd("empty config file")
		return errors.New("empty config file")
	}
	if homeDir == "" {
		homeDir = filepath.Dir(configFile)
	}
	if running {
		shutdownLocked()
	}
	if dialer.DefaultSocketHook == nil {
		log.Warnln("[ClashMiCore] Android socket protector is not installed; outbound sockets may route back into VPN")
	}

	log.Infoln("[ClashMiCore] start config=%s patch=%s finalPatch=%s home=%s fd=%d controller=%s", configFile, patchFile, finalPatchFile, homeDir, tunFd, externalController)
	runtimeConfig, err := buildRuntimeConfigWithMetadata(configFile, patchFile, finalPatchFile, tunFd)
	if err != nil {
		closeOwnedTunFd("build runtime config failed")
		return err
	}

	if err = os.Setenv("SAFE_PATHS", homeDir); err != nil {
		closeOwnedTunFd("set safe paths failed")
		return err
	}
	if err = os.Setenv("SKIP_SAFE_PATH_CHECK", "true"); err != nil {
		closeOwnedTunFd("set skip safe path check failed")
		return err
	}

	C.SetHomeDir(homeDir)
	C.SetConfig(configFile)
	if err = config.Init(C.Path.HomeDir()); err != nil {
		closeOwnedTunFd("init config dir failed")
		return fmt.Errorf("init mihomo config dir: %w", err)
	}

	options := []hub.Option{}
	if externalController != "" {
		options = append(options, hub.WithExternalController(externalController))
	}
	if secret != "" {
		options = append(options, hub.WithSecret(secret))
	}
	ownsTunFd = false
	cfg, err := executor.ParseWithBytes(runtimeConfig.data)
	if err != nil {
		executor.Shutdown()
		return fmt.Errorf("parse/apply mihomo config: %w", err)
	}
	for _, option := range options {
		option(cfg)
	}
	hub.ApplyConfig(cfg)
	tunConf := listener.GetTunConf()
	if !tunConf.Enable {
		executor.Shutdown()
		return fmt.Errorf("mihomo TUN listener did not start (stack=%s fd=%d); make sure the Android core supports the requested stack", tunConf.Stack.String(), tunFd)
	}

	statistic.DefaultManager.ResetStatistic()
	running = true
	lastHome = homeDir
	mergeStartupRuntimeConfigState(cfg.DNS, cfg.General.IPv6, runtimeConfig.injectedDNSPolicyHosts)
	log.Infoln("[ClashMiCore] started stack=%s fd=%d address=%v", tunConf.Stack.String(), tunConf.FileDescriptor, tunConf.Inet4Address)
	return nil
}

func Stop() {
	mu.Lock()
	defer mu.Unlock()
	shutdownLocked()
}

func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

func Traffic() string {
	up, down := statistic.DefaultManager.Now()
	body, _ := json.Marshal(map[string]int64{
		"up":   up,
		"down": down,
	})
	return string(body)
}

func Connections(withConnectionsList bool) string {
	snapshot := statistic.DefaultManager.Snapshot()
	if !withConnectionsList {
		snapshot.Connections = nil
	}
	body, err := json.Marshal(snapshot)
	if err != nil {
		return `{"uploadTotal":0,"downloadTotal":0,"memory":0,"connections":[]}`
	}
	return string(body)
}

func TunInfo() string {
	tunConf := listener.GetTunConf()
	body, err := json.Marshal(map[string]any{
		"enable":         tunConf.Enable,
		"stack":          tunConf.Stack.String(),
		"fileDescriptor": tunConf.FileDescriptor,
		"inet4Address":   fmt.Sprint(tunConf.Inet4Address),
		"mtu":            tunConf.MTU,
	})
	if err != nil {
		return `{"enable":false}`
	}
	return string(body)
}

func HomeDir() string {
	mu.Lock()
	defer mu.Unlock()
	return lastHome
}

func shutdownLocked() {
	if !running {
		return
	}
	log.Warnln("[ClashMiCore] stopping")
	executor.Shutdown()
	statistic.DefaultManager.ResetStatistic()
	running = false
	clearRuntimeConfigStateLocked()
	log.Warnln("[ClashMiCore] stopped")
}

func clearRuntimeConfigStateLocked() {
	runtimeConfigMu.Lock()
	defer runtimeConfigMu.Unlock()
	lastDNSConfig = nil
	lastGeneralIPv6 = false
	lastDNSPolicyHosts = nil
}

func refreshAndroidTailscaleDNSPolicy() error {
	mu.Lock()
	defer mu.Unlock()
	if !running {
		return nil
	}

	runtimeConfigMu.Lock()
	defer runtimeConfigMu.Unlock()
	if lastDNSConfig == nil {
		return errors.New("runtime DNS config state is missing")
	}
	if len(lastDNSPolicyHosts) == 0 {
		return nil
	}

	nameservers, err := parseAndroidPhysicalNameservers(androidPhysicalDNSServers())
	if err != nil {
		return err
	}
	dnsConfig := cloneDNSConfig(lastDNSConfig)
	dnsConfig.NameServerPolicy = replaceDNSPoliciesForHosts(dnsConfig.NameServerPolicy, lastDNSPolicyHosts, nameservers)
	applyRuntimeDNSConfig(dnsConfig, lastGeneralIPv6)
	mihomoResolver.ResetConnection()
	lastDNSConfig = cloneDNSConfig(dnsConfig)
	log.Infoln("[ClashMiCore] Android physical DNS policy refreshed after network info update hosts=%s servers=%d", strings.Join(lastDNSPolicyHosts, ","), len(nameservers))
	return nil
}

func setRuntimeConfigState(dnsConfig *config.DNS, generalIPv6 bool, dnsPolicyHosts []string) {
	runtimeConfigMu.Lock()
	defer runtimeConfigMu.Unlock()
	lastDNSConfig = cloneDNSConfig(dnsConfig)
	lastGeneralIPv6 = generalIPv6
	lastDNSPolicyHosts = append([]string(nil), dnsPolicyHosts...)
}

func mergeStartupRuntimeConfigState(dnsConfig *config.DNS, generalIPv6 bool, dnsPolicyHosts []string) {
	runtimeConfigMu.Lock()
	defer runtimeConfigMu.Unlock()
	if lastDNSConfig == nil {
		lastDNSConfig = cloneDNSConfig(dnsConfig)
	}
	lastGeneralIPv6 = generalIPv6
	lastDNSPolicyHosts = mergeDNSPolicyHosts(lastDNSPolicyHosts, dnsPolicyHosts)
	log.Infoln("[ClashMiCore] Android physical DNS policy startup state synced hosts=%s", strings.Join(lastDNSPolicyHosts, ","))
}

func mergeDNSPolicyHosts(existing []string, incoming []string) []string {
	if len(existing) == 0 {
		return append([]string(nil), incoming...)
	}
	merged := append([]string(nil), existing...)
	seen := make(map[string]bool, len(existing)+len(incoming))
	for _, host := range existing {
		seen[strings.ToLower(host)] = true
	}
	for _, host := range incoming {
		key := strings.ToLower(host)
		if seen[key] {
			continue
		}
		seen[key] = true
		merged = append(merged, host)
	}
	return merged
}

func syncRuntimeConfigStateFromAppliedConfig(cfg *config.Config) {
	syncRuntimeConfigStateFromAppliedConfigWithServers(cfg, androidPhysicalDNSServers())
}

func syncRuntimeConfigStateFromAppliedConfigWithServers(cfg *config.Config, servers []string) {
	if cfg == nil || cfg.DNS == nil || cfg.General == nil {
		return
	}
	controlHosts := tailscaleControlHostsFromConfig(cfg)
	setTailscaleControlHTTPProxy(findLocalHTTPProxyURLFromGeneral(cfg.General))

	runtimeConfigMu.Lock()
	defer runtimeConfigMu.Unlock()
	dnsConfig := cloneDNSConfig(cfg.DNS)
	generalIPv6 := cfg.General.IPv6
	trackedHosts := filterDNSPolicyHostsForCurrentPolicies(controlHosts, dnsConfig.NameServerPolicy)
	lastDNSConfig = cloneDNSConfig(dnsConfig)
	lastGeneralIPv6 = generalIPv6
	lastDNSPolicyHosts = append([]string(nil), trackedHosts...)
	if len(trackedHosts) == 0 {
		log.Infoln("[ClashMiCore] synced Android physical DNS policy cache from applied Mihomo config hosts=")
		return
	}

	nameservers, err := parseAndroidPhysicalNameservers(servers)
	if err != nil {
		log.Warnln("[ClashMiCore] Android physical DNS policy not reapplied after config reload: %v", err)
		return
	}
	if len(nameservers) == 0 {
		log.Warnln("[ClashMiCore] Android physical DNS policy cache synced without current servers hosts=%s", strings.Join(trackedHosts, ","))
		return
	}
	dnsConfig.NameServerPolicy = replaceDNSPoliciesForHosts(dnsConfig.NameServerPolicy, trackedHosts, nameservers)
	applyRuntimeDNSConfig(dnsConfig, generalIPv6)
	mihomoResolver.ResetConnection()
	lastDNSConfig = cloneDNSConfig(dnsConfig)
	log.Infoln("[ClashMiCore] Android physical DNS policy reapplied after config reload hosts=%s servers=%d", strings.Join(trackedHosts, ","), len(nameservers))
}

func parseAndroidPhysicalNameservers(servers []string) ([]mihomoDNS.NameServer, error) {
	if len(servers) == 0 {
		return nil, nil
	}
	if mihomoDNS.ParseNameServer == nil {
		return nil, errors.New("mihomo DNS nameserver parser is not initialized")
	}
	nameservers, err := mihomoDNS.ParseNameServer(androidPhysicalNameserverURLs(servers))
	if err != nil {
		return nil, fmt.Errorf("parse Android physical DNS nameservers: %w", err)
	}
	return nameservers, nil
}

func replaceDNSPoliciesForHosts(policies []mihomoDNS.Policy, hosts []string, nameservers []mihomoDNS.NameServer) []mihomoDNS.Policy {
	hostSet := map[string]bool{}
	for _, host := range hosts {
		hostSet[strings.ToLower(host)] = true
	}

	replaced := map[string]bool{}
	next := make([]mihomoDNS.Policy, 0, len(policies)+len(hosts))
	for _, policy := range policies {
		host := strings.ToLower(policy.Domain)
		if policy.Matcher != nil || !hostSet[host] {
			next = append(next, cloneDNSPolicy(policy))
			continue
		}
		replaced[host] = true
		if len(nameservers) == 0 {
			continue
		}
		policy.NameServers = cloneNameServers(nameservers)
		next = append(next, cloneDNSPolicy(policy))
	}

	if len(nameservers) == 0 {
		return next
	}
	for _, host := range hosts {
		host = strings.ToLower(host)
		if replaced[host] {
			continue
		}
		next = append(next, mihomoDNS.Policy{Domain: host, NameServers: cloneNameServers(nameservers)})
	}
	return next
}

func filterDNSPolicyHostsForCurrentPolicies(hosts []string, policies []mihomoDNS.Policy) []string {
	if len(hosts) == 0 {
		return nil
	}
	next := make([]string, 0, len(hosts))
	for _, host := range hosts {
		if dnsPoliciesCoverHost(policies, host) {
			log.Infoln("[ClashMiCore] Android physical DNS policy host no longer tracked; live DNS policy already covers host=%s", host)
			continue
		}
		next = append(next, host)
	}
	return next
}

func dnsPoliciesCoverHost(policies []mihomoDNS.Policy, host string) bool {
	for _, policy := range policies {
		if policy.Matcher != nil && policy.Matcher.MatchDomain(host) {
			return true
		}
		if policy.Domain != "" && dnsPolicyDomainCoversHost(policy.Domain, host) {
			return true
		}
	}
	return false
}

type tailscaleControlURLProvider interface {
	TailscaleControlURL() string
}

func tailscaleControlHostsFromConfig(cfg *config.Config) []string {
	seen := map[string]bool{}
	hosts := make([]string, 0)
	for _, proxy := range cfg.Proxies {
		collectTailscaleControlHostFromProxy(&hosts, seen, proxy)
	}
	for _, provider := range cfg.Providers {
		if provider == nil {
			continue
		}
		for _, proxy := range provider.Proxies() {
			collectTailscaleControlHostFromProxy(&hosts, seen, proxy)
		}
	}
	sort.Strings(hosts)
	return hosts
}

func collectTailscaleControlHostFromProxy(hosts *[]string, seen map[string]bool, proxy C.Proxy) {
	if proxy == nil {
		return
	}
	adapter := proxy.Adapter()
	if adapter == nil || adapter.Type() != C.Tailscale {
		return
	}
	controlURL := ""
	if tailscale, ok := adapter.(tailscaleControlURLProvider); ok {
		controlURL = tailscale.TailscaleControlURL()
	}
	host, ok := tailscaleControlHostFromURL(controlURL)
	if !ok || seen[host] {
		return
	}
	seen[host] = true
	*hosts = append(*hosts, host)
}

func cloneDNSConfig(c *config.DNS) *config.DNS {
	if c == nil {
		return nil
	}
	clone := *c
	clone.NameServer = cloneNameServers(c.NameServer)
	clone.Fallback = cloneNameServers(c.Fallback)
	clone.FallbackIPFilter = append([]C.IpMatcher(nil), c.FallbackIPFilter...)
	clone.FallbackDomainFilter = append([]C.DomainMatcher(nil), c.FallbackDomainFilter...)
	clone.DefaultNameserver = cloneNameServers(c.DefaultNameserver)
	clone.NameServerPolicy = cloneDNSPolicies(c.NameServerPolicy)
	clone.ProxyServerNameserver = cloneNameServers(c.ProxyServerNameserver)
	clone.ProxyServerPolicy = cloneDNSPolicies(c.ProxyServerPolicy)
	clone.DirectNameServer = cloneNameServers(c.DirectNameServer)
	return &clone
}

func cloneDNSPolicies(policies []mihomoDNS.Policy) []mihomoDNS.Policy {
	if policies == nil {
		return nil
	}
	clone := make([]mihomoDNS.Policy, len(policies))
	for i, policy := range policies {
		clone[i] = cloneDNSPolicy(policy)
	}
	return clone
}

func cloneDNSPolicy(policy mihomoDNS.Policy) mihomoDNS.Policy {
	policy.NameServers = cloneNameServers(policy.NameServers)
	return policy
}

func cloneNameServers(nameservers []mihomoDNS.NameServer) []mihomoDNS.NameServer {
	if nameservers == nil {
		return nil
	}
	clone := make([]mihomoDNS.NameServer, len(nameservers))
	for i, nameserver := range nameservers {
		clone[i] = nameserver
		if nameserver.Params != nil {
			clone[i].Params = map[string]string{}
			for key, value := range nameserver.Params {
				clone[i].Params[key] = value
			}
		}
	}
	return clone
}

func applyRuntimeDNSConfig(c *config.DNS, generalIPv6 bool) {
	if !c.Enable {
		mihomoResolver.DefaultResolver = nil
		mihomoResolver.DefaultHostMapper = nil
		mihomoResolver.DefaultService = nil
		mihomoResolver.ProxyServerHostResolver = nil
		mihomoResolver.DirectHostResolver = nil
		mihomoDNS.ReCreateServer("", nil)
		return
	}

	ipv6 := c.IPv6 && generalIPv6
	r := mihomoDNS.NewResolver(mihomoDNS.Config{
		Main:                 c.NameServer,
		Fallback:             c.Fallback,
		IPv6:                 ipv6,
		IPv6Timeout:          c.IPv6Timeout,
		FallbackIPFilter:     c.FallbackIPFilter,
		FallbackDomainFilter: c.FallbackDomainFilter,
		Default:              c.DefaultNameserver,
		Policy:               c.NameServerPolicy,
		ProxyServer:          c.ProxyServerNameserver,
		ProxyServerPolicy:    c.ProxyServerPolicy,
		DirectServer:         c.DirectNameServer,
		DirectFollowPolicy:   c.DirectFollowPolicy,
		CacheAlgorithm:       c.CacheAlgorithm,
		CacheMaxSize:         c.CacheMaxSize,
	})
	m := mihomoDNS.NewEnhancer(mihomoDNS.EnhancerConfig{
		IPv6:          ipv6,
		EnhancedMode:  c.EnhancedMode,
		FakeIPPool:    c.FakeIPPool,
		FakeIPPool6:   c.FakeIPPool6,
		FakeIPSkipper: c.FakeIPSkipper,
		FakeIPTTL:     c.FakeIPTTL,
		UseHosts:      c.UseHosts,
	})

	if old := mihomoResolver.DefaultHostMapper; old != nil {
		if oldMapper, ok := old.(*mihomoDNS.ResolverEnhancer); ok {
			m.PatchFrom(oldMapper)
		}
	}

	s := mihomoDNS.NewService(r.Resolver, m)

	mihomoResolver.DefaultResolver = r
	mihomoResolver.DefaultHostMapper = m
	mihomoResolver.DefaultService = s
	mihomoResolver.UseSystemHosts = c.UseSystemHosts

	if r.ProxyResolver.Invalid() {
		mihomoResolver.ProxyServerHostResolver = r.ProxyResolver
	} else {
		mihomoResolver.ProxyServerHostResolver = r.Resolver
	}

	if r.DirectResolver.Invalid() {
		mihomoResolver.DirectHostResolver = r.DirectResolver
	} else {
		mihomoResolver.DirectHostResolver = r.Resolver
	}

	mihomoDNS.ReCreateServer(c.Listen, s)
}

func protectSocket(protector SocketProtector, network string, address string, conn syscall.RawConn) error {
	var protectErr error
	if err := conn.Control(func(fd uintptr) {
		protectErr = protectSocketFD(protector, fd, network, address)
	}); err != nil {
		return fmt.Errorf("protect socket control failed network=%s address=%s: %w", network, address, err)
	}
	return protectErr
}

func protectSocketFD(protector SocketProtector, fd uintptr, network string, address string) error {
	if !protector.Protect(int64(fd)) {
		protectErr := fmt.Errorf("VpnService.protect returned false for fd=%d network=%s address=%s", fd, network, address)
		log.Warnln("[ClashMiCore] %v", protectErr)
		return protectErr
	}
	return nil
}

type runtimeConfigBuild struct {
	data                   []byte
	injectedDNSPolicyHosts []string
}

func buildRuntimeConfig(configFile string, patchFile string, finalPatchFile string, tunFd int) ([]byte, error) {
	runtimeConfig, err := buildRuntimeConfigWithMetadata(configFile, patchFile, finalPatchFile, tunFd)
	if err != nil {
		return nil, err
	}
	return runtimeConfig.data, nil
}

func buildRuntimeConfigWithMetadata(configFile string, patchFile string, finalPatchFile string, tunFd int) (*runtimeConfigBuild, error) {
	root, err := readMergedConfigRoot(configFile, patchFile, finalPatchFile)
	if err != nil {
		return nil, err
	}

	tun := ensureMapping(root, "tun")
	setBool(tun, "enable", true)
	setInt(tun, "file-descriptor", tunFd)
	setBool(tun, "auto-route", false)
	setBool(tun, "auto-detect-interface", false)
	setInt(tun, "mtu", androidTunMTU)
	if findValue(tun, "stack") == nil {
		setScalar(tun, "stack", defaultAndroidTunStack)
	}
	if findValue(tun, "dns-hijack") == nil {
		setSequence(tun, "dns-hijack", []string{"0.0.0.0:53"})
	}
	if scalarBool(findValue(root, "ipv6")) && findValue(tun, "inet6-address") == nil {
		setSequence(tun, "inet6-address", []string{androidTunIPv6Address})
	}

	dns := ensureMapping(root, "dns")
	setScalar(dns, "fake-ip-range", androidTunFakeIPRange)
	injectedDNSPolicyHosts := injectAndroidTailscaleDNSPolicy(root, dns)

	proxyURL := findLocalHTTPProxyURL(root)
	logTailscaleControlRoutingConfig(root, proxyURL)
	setTailscaleControlHTTPProxy(proxyURL)

	out, err := yaml.Marshal(root)
	if err != nil {
		return nil, err
	}
	return &runtimeConfigBuild{
		data:                   out,
		injectedDNSPolicyHosts: injectedDNSPolicyHosts,
	}, nil
}

func EffectiveIPv6(configFile string, patchFile string, finalPatchFile string) (bool, error) {
	root, err := readMergedConfigRoot(configFile, patchFile, finalPatchFile)
	if err != nil {
		return false, err
	}
	return scalarBool(findValue(root, "ipv6")), nil
}

func logTailscaleControlRoutingConfig(root *yaml.Node, proxyURL string) {
	if !hasTailscaleProxy(root) {
		return
	}
	if proxyURL == "" {
		log.Warnln("[ClashMiCore] Tailscale control traffic will use config routes only; no local mixed-port/port was found")
		return
	}
	if hasTailscaleControlRoutingRule(root) {
		log.Infoln("[ClashMiCore] Tailscale control traffic will use local Mihomo proxy and configured rules")
		return
	}
	log.Warnln("[ClashMiCore] Tailscale control traffic will use local Mihomo proxy, but config has no explicit controlplane route; add DOMAIN,controlplane.tailscale.com,<proxy> or DOMAIN-SUFFIX,tailscale.com,<proxy>")
}

func injectAndroidTailscaleDNSPolicy(root *yaml.Node, dns *yaml.Node) []string {
	servers := androidPhysicalDNSServers()
	return injectAndroidTailscaleDNSPolicyWithServers(root, dns, servers)
}

func injectAndroidTailscaleDNSPolicyWithServers(root *yaml.Node, dns *yaml.Node, servers []string) []string {
	controlHosts := tailscaleControlHosts(root)
	if len(controlHosts) == 0 {
		return nil
	}

	policy := findValue(dns, "nameserver-policy")
	if policy != nil && policy.Kind != yaml.MappingNode {
		log.Warnln("[ClashMiCore] Android physical DNS not injected; dns.nameserver-policy is not a mapping")
		return nil
	}

	policyHosts := make([]string, 0, len(controlHosts))
	for _, host := range controlHosts {
		if policy != nil && hasDNSPolicyForHost(policy, host) {
			log.Infoln("[ClashMiCore] Android physical DNS not injected for Tailscale control host %s; dns.nameserver-policy already covers it", host)
			continue
		}
		policyHosts = append(policyHosts, host)
	}
	if len(policyHosts) == 0 {
		return nil
	}
	if len(servers) == 0 {
		log.Warnln("[ClashMiCore] Android physical DNS policy hosts tracked without current servers hosts=%s", strings.Join(policyHosts, ","))
		return policyHosts
	}
	if policy == nil {
		policy = &yaml.Node{Kind: yaml.MappingNode}
		setNode(dns, "nameserver-policy", policy)
	}

	nameservers := androidPhysicalNameserverURLs(servers)
	for _, host := range policyHosts {
		setSequence(policy, host, nameservers)
	}
	log.Infoln("[ClashMiCore] Android physical DNS scoped to Tailscale control DNS policy hosts=%s servers=%s proxy=%s", strings.Join(policyHosts, ","), strings.Join(servers, ","), androidPhysicalDNSProxyName)
	return policyHosts
}

func hasDNSPolicyForHost(policy *yaml.Node, host string) bool {
	host = strings.ToLower(host)
	for i := 0; i+1 < len(policy.Content); i += 2 {
		keyNode := policy.Content[i]
		if keyNode.Kind != yaml.ScalarNode {
			continue
		}
		for _, rawKey := range strings.Split(keyNode.Value, ",") {
			key := strings.TrimSpace(strings.ToLower(rawKey))
			if dnsPolicyDomainCoversHost(key, host) {
				return true
			}
		}
	}
	return false
}

func dnsPolicyDomainCoversHost(policyDomain string, host string) bool {
	tree := trie.New[struct{}]()
	if err := tree.Insert(policyDomain, struct{}{}); err != nil {
		return false
	}
	return tree.Search(host) != nil
}

func tailscaleControlHosts(root *yaml.Node) []string {
	seen := map[string]bool{}
	hosts := make([]string, 0)
	collectTailscaleControlHosts(&hosts, seen, findValue(root, "proxies"))

	providers := findValue(root, "proxy-providers")
	if providers == nil {
		return hosts
	}
	if providers.Kind != yaml.MappingNode {
		log.Warnln("[ClashMiCore] Android physical DNS skipped proxy-providers scan; proxy-providers is not a mapping")
		return hosts
	}
	for i := 0; i+1 < len(providers.Content); i += 2 {
		provider := providers.Content[i+1]
		if provider.Kind != yaml.MappingNode {
			continue
		}
		collectTailscaleControlHosts(&hosts, seen, findValue(provider, "payload"))
	}
	return hosts
}

func collectTailscaleControlHosts(hosts *[]string, seen map[string]bool, proxies *yaml.Node) {
	if proxies == nil || proxies.Kind != yaml.SequenceNode {
		return
	}
	for _, proxy := range proxies.Content {
		if proxy.Kind != yaml.MappingNode {
			continue
		}
		if !strings.EqualFold(scalarString(findValue(proxy, "type")), "tailscale") {
			continue
		}
		host, ok := tailscaleControlHost(proxy)
		if !ok || seen[host] {
			continue
		}
		seen[host] = true
		*hosts = append(*hosts, host)
	}
}

func tailscaleControlHost(proxy *yaml.Node) (string, bool) {
	controlURL := strings.TrimSpace(scalarString(findValue(proxy, "control-url")))
	return tailscaleControlHostFromURL(controlURL)
}

func tailscaleControlHostFromURL(controlURL string) (string, bool) {
	controlURL = strings.TrimSpace(controlURL)
	if controlURL == "" {
		return "controlplane.tailscale.com", true
	}
	parsed, err := url.Parse(controlURL)
	if err != nil {
		log.Warnln("[ClashMiCore] Android physical DNS not injected for invalid Tailscale control-url=%s error=%v", controlURL, err)
		return "", false
	}
	host := strings.TrimSuffix(strings.ToLower(parsed.Hostname()), ".")
	if host == "" || net.ParseIP(host) != nil || !strings.Contains(host, ".") {
		log.Warnln("[ClashMiCore] Android physical DNS not injected for unsupported Tailscale control host=%s", host)
		return "", false
	}
	return host, true
}

func androidPhysicalNameserverURLs(servers []string) []string {
	nameservers := make([]string, 0, len(servers))
	for _, server := range servers {
		nameservers = append(nameservers, androidPhysicalNameserverURL(server))
	}
	return nameservers
}

func androidPhysicalNameserverURL(server string) string {
	return (&url.URL{Scheme: "udp", Host: server, Fragment: androidPhysicalDNSProxyName}).String()
}

func findLocalHTTPProxyURL(root *yaml.Node) string {
	host := localHTTPProxyHost(root)
	for _, key := range []string{"mixed-port", "port"} {
		port, ok := scalarInt(findValue(root, key))
		if !ok || port <= 0 {
			continue
		}
		proxyURL := &url.URL{
			Scheme: "http",
			Host:   net.JoinHostPort(host, strconv.Itoa(port)),
		}
		if host != "127.0.0.1" {
			log.Infoln("[ClashMiCore] Tailscale control proxy will use configured local proxy bind address %s", host)
		}
		if user, pass, ok := firstLocalProxyAuthentication(root); ok {
			proxyURL.User = url.UserPassword(user, pass)
			log.Infoln("[ClashMiCore] Tailscale control proxy will use configured local proxy authentication")
		}
		return proxyURL.String()
	}
	return ""
}

func findLocalHTTPProxyURLFromGeneral(general *config.General) string {
	if general == nil {
		return ""
	}
	host := localHTTPProxyHostFromValues(general.AllowLan, general.BindAddress)
	for _, port := range []int{general.MixedPort, general.Port} {
		if port <= 0 {
			continue
		}
		proxyURL := &url.URL{
			Scheme: "http",
			Host:   net.JoinHostPort(host, strconv.Itoa(port)),
		}
		if host != "127.0.0.1" {
			log.Infoln("[ClashMiCore] Tailscale control proxy will use configured local proxy bind address %s", host)
		}
		if user, pass, ok := firstLocalProxyAuthenticationRecord(general.Authentication); ok {
			proxyURL.User = url.UserPassword(user, pass)
			log.Infoln("[ClashMiCore] Tailscale control proxy will use configured local proxy authentication")
		}
		return proxyURL.String()
	}
	return ""
}

func localHTTPProxyHost(root *yaml.Node) string {
	return localHTTPProxyHostFromValues(scalarBool(findValue(root, "allow-lan")), scalarString(findValue(root, "bind-address")))
}

func localHTTPProxyHostFromValues(allowLan bool, bindAddress string) string {
	if !allowLan {
		return "127.0.0.1"
	}
	bindAddress = strings.TrimSpace(bindAddress)
	if bindAddress == "" || bindAddress == "*" {
		return "127.0.0.1"
	}
	host := strings.Trim(bindAddress, "[]")
	if ip := net.ParseIP(host); ip != nil && ip.IsUnspecified() {
		if ip.To4() != nil {
			return "127.0.0.1"
		}
		return "::1"
	}
	return host
}

func firstLocalProxyAuthentication(root *yaml.Node) (string, string, bool) {
	authentication := findValue(root, "authentication")
	if authentication == nil {
		return "", "", false
	}
	if authentication.Kind != yaml.SequenceNode {
		log.Warnln("[ClashMiCore] Tailscale control proxy authentication ignored; authentication is not a sequence")
		return "", "", false
	}
	records := make([]string, 0, len(authentication.Content))
	for _, record := range authentication.Content {
		if record.Kind != yaml.ScalarNode {
			continue
		}
		records = append(records, record.Value)
	}
	if user, pass, ok := firstLocalProxyAuthenticationRecord(records); ok {
		return user, pass, true
	}
	log.Warnln("[ClashMiCore] Tailscale control proxy authentication ignored; no valid authentication record found")
	return "", "", false
}

func firstLocalProxyAuthenticationRecord(records []string) (string, string, bool) {
	for _, record := range records {
		if user, pass, ok := strings.Cut(record, ":"); ok {
			return user, pass, true
		}
	}
	return "", "", false
}

func hasTailscaleProxy(root *yaml.Node) bool {
	proxies := findValue(root, "proxies")
	if proxies == nil || proxies.Kind != yaml.SequenceNode {
		return false
	}
	for _, proxy := range proxies.Content {
		if proxy.Kind != yaml.MappingNode {
			continue
		}
		if strings.EqualFold(scalarString(findValue(proxy, "type")), "tailscale") {
			return true
		}
	}
	return false
}

func hasTailscaleControlRoutingRule(root *yaml.Node) bool {
	rules := findValue(root, "rules")
	if rules == nil || rules.Kind != yaml.SequenceNode {
		return false
	}
	for _, rule := range rules.Content {
		if rule.Kind != yaml.ScalarNode {
			continue
		}
		parts := strings.Split(rule.Value, ",")
		if len(parts) < 2 {
			continue
		}
		ruleType := strings.TrimSpace(parts[0])
		payload := strings.TrimSpace(parts[1])
		if strings.EqualFold(ruleType, "DOMAIN") && strings.EqualFold(payload, "controlplane.tailscale.com") {
			return true
		}
		if strings.EqualFold(ruleType, "DOMAIN-SUFFIX") && strings.EqualFold(payload, "tailscale.com") {
			return true
		}
	}
	return false
}

func scalarInt(node *yaml.Node) (int, bool) {
	if node == nil || node.Kind != yaml.ScalarNode {
		return 0, false
	}
	value, err := strconv.Atoi(node.Value)
	if err != nil {
		return 0, false
	}
	return value, true
}

func scalarString(node *yaml.Node) string {
	if node == nil || node.Kind != yaml.ScalarNode {
		return ""
	}
	return node.Value
}

func scalarBool(node *yaml.Node) bool {
	if node == nil || node.Kind != yaml.ScalarNode {
		return false
	}
	return node.Value == "true"
}

func readMergedConfigRoot(configFile string, patchFile string, finalPatchFile string) (*yaml.Node, error) {
	root, err := readYamlMapping(configFile, true)
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", configFile, err)
	}
	if patchFile != "" {
		patch, patchErr := readYamlMapping(patchFile, false)
		if patchErr != nil {
			return nil, fmt.Errorf("read patch %s: %w", patchFile, patchErr)
		}
		if patch != nil {
			mergeMapping(root, patch)
		}
	}
	if finalPatchFile != "" {
		patch, patchErr := readYamlMapping(finalPatchFile, false)
		if patchErr != nil {
			return nil, fmt.Errorf("read final patch %s: %w", finalPatchFile, patchErr)
		}
		if patch != nil {
			mergeMapping(root, patch)
		}
	}
	return root, nil
}

func readYamlMapping(path string, required bool) (*yaml.Node, error) {
	info, err := os.Stat(path)
	if err != nil {
		if required || !errors.Is(err, os.ErrNotExist) {
			return nil, err
		}
		return nil, nil
	}
	if info.IsDir() {
		return nil, fmt.Errorf("path is directory")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 && !required {
		return nil, nil
	}
	var doc yaml.Node
	if err = yaml.Unmarshal(data, &doc); err != nil {
		return nil, err
	}
	if len(doc.Content) == 0 || doc.Content[0].Kind == 0 {
		if required {
			return nil, errors.New("empty yaml")
		}
		return nil, nil
	}
	node := doc.Content[0]
	if node.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("root is not a mapping")
	}
	return node, nil
}

func mergeMapping(dst *yaml.Node, patch *yaml.Node) {
	for i := 0; i+1 < len(patch.Content); i += 2 {
		key := patch.Content[i]
		value := patch.Content[i+1]
		if shouldSkipPatchKey(key.Value) {
			continue
		}
		current := findValue(dst, key.Value)
		if current != nil && current.Kind == yaml.MappingNode && value.Kind == yaml.MappingNode {
			mergeMapping(current, value)
			continue
		}
		setNode(dst, key.Value, cloneNode(value))
	}
}

func shouldSkipPatchKey(key string) bool {
	switch key {
	case "overwrite-rule-providers", "overwrite-rules", "overwrite-sub-rules", "overwrite-proxy-groups", "overwrite-hosts", "extension":
		return true
	default:
		return false
	}
}

func ensureMapping(root *yaml.Node, key string) *yaml.Node {
	if node := findValue(root, key); node != nil && node.Kind == yaml.MappingNode {
		return node
	}
	node := &yaml.Node{Kind: yaml.MappingNode}
	setNode(root, key, node)
	return node
}

func setScalar(root *yaml.Node, key string, value string) {
	setNode(root, key, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value})
}

func setBool(root *yaml.Node, key string, value bool) {
	setNode(root, key, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!bool", Value: fmt.Sprintf("%t", value)})
}

func setInt(root *yaml.Node, key string, value int) {
	setNode(root, key, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!int", Value: fmt.Sprintf("%d", value)})
}

func setSequence(root *yaml.Node, key string, values []string) {
	node := &yaml.Node{Kind: yaml.SequenceNode}
	for _, value := range values {
		node.Content = append(node.Content, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value})
	}
	setNode(root, key, node)
}

func setNode(root *yaml.Node, key string, value *yaml.Node) {
	for i := 0; i+1 < len(root.Content); i += 2 {
		if root.Content[i].Value == key {
			root.Content[i+1] = value
			return
		}
	}
	root.Content = append(root.Content, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: key}, value)
}

func findValue(root *yaml.Node, key string) *yaml.Node {
	for i := 0; i+1 < len(root.Content); i += 2 {
		if root.Content[i].Value == key {
			return root.Content[i+1]
		}
	}
	return nil
}

func cloneNode(node *yaml.Node) *yaml.Node {
	if node == nil {
		return nil
	}
	clone := *node
	if len(node.Content) > 0 {
		clone.Content = make([]*yaml.Node, len(node.Content))
		for i, child := range node.Content {
			clone.Content[i] = cloneNode(child)
		}
	}
	return &clone
}
